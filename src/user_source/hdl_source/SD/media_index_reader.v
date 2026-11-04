module media_index_reader #(
    parameter integer VIDEO_FILE_SIZE=30592512,VIDEO_FILE1_SIZE=24832512,VIDEO_FILE2_SIZE=22784512,
    parameter integer WAV_FILE0_SIZE=3824044,WAV_FILE1_SIZE=3104044,WAV_FILE2_SIZE=2848044,
    parameter integer MAX_LBA=524288,LBA_BITS=19,
    parameter integer TIMEOUT_CYCLES = 100_000_000
)(
    input clk, input rst, input start, input sd_init_done,input[1:0] program_select,input[3:0] image_select,
    output reg[3:0] image_lookup_slot,output reg[31:0] image_lookup_lba,image_lookup_size,output reg image_lookup_valid,
    output reg sd_sec_read,
    output [31:0] sd_sec_read_addr,
    input [7:0] sd_sec_read_data,
    input sd_sec_read_data_valid, input sd_sec_read_end,
    output reg done, output reg failed, output reg [3:0] error_code,
    output [3:0] image_count,
    output [287:0] image_lbas, output [287:0] image_sizes,
    output reg [287:0] image_types, output reg [287:0] image_sectors,
    output reg [287:0] image_ids,
    output reg wav_present,output reg [31:0] wav_lba,output reg [31:0] wav_size,
    output video_wav_present,output [31:0] video_wav_lba,output [31:0] video_wav_size,
    output video_present,output [31:0] video_lba,output [31:0] video_size
);
localparam IDLE=0, READ=1, RAM_WAIT=2, RAM_BYTE=3, WORD_READY=4,
           CALCULATE=5, CHECK_ENTRY=6, ENTRY_RESULT=7, CHECK_OVERLAP=8,
           OVERLAP_RESULT=9, COMMIT=10, NEXT_ENTRY=11, FINISH=12, ERROR=13;
localparam HEADER_WORD=0, ENTRY_WORD=1, PRIOR_LBA=2, PRIOR_SECTORS=3;
reg [3:0] state;
reg [1:0] fetch_context;reg lookup_mode;reg[3:0] lookup_slot;
reg [9:0] byte_count;
reg [$clog2(TIMEOUT_CYCLES+1)-1:0] timer;
reg reserved_bad;
(* ram_style="block" *) reg [7:0] index_bytes [0:511];
reg [7:0] ram_q;
reg [6:0] word_index,entry_base,scan_word;
reg [1:0] byte_lane;
reg [31:0] word_value;
reg [2:0] field;reg [3:0] entry_idx,bmp_count,prior_idx;reg[4:0]entry_count;
reg [1:0] current_kind;
reg kind_bad,entry_nonzero,current_reserved_bad,entry_bad,overlap_bad;
reg [31:0] current_lba,current_size,current_sectors,current_id;
reg [LBA_BITS:0] current_end,prior_end;
reg [31:0] expected_sectors;reg[LBA_BITS-1:0]prior_lba;
reg[35:0] image_entry_positions;
reg [9*LBA_BITS-1:0] image_lbas_compact;
reg [242:0] image_sizes_compact;
wire[1:0]video_slot=current_id[1:0]-2'd1;wire[1:0]soundtrack_slot=current_id[1:0]-2'd2;
reg[3*LBA_BITS-1:0] video_lbas_table,soundtrack_lbas_table;reg[2:0]video_seen,soundtrack_seen;
function[31:0] clip_file;input[1:0] id;begin case(id)0:clip_file=VIDEO_FILE_SIZE;1:clip_file=VIDEO_FILE1_SIZE;default:clip_file=VIDEO_FILE2_SIZE;endcase end endfunction
function[31:0] clip_wav;input[1:0] id;begin case(id)0:clip_wav=WAV_FILE0_SIZE;1:clip_wav=WAV_FILE1_SIZE;default:clip_wav=WAV_FILE2_SIZE;endcase end endfunction
assign video_present=program_select<3 && video_seen[program_select];
assign video_wav_present=program_select<3 && soundtrack_seen[program_select];
assign video_lba={{(32-LBA_BITS){1'b0}},video_lbas_table[program_select*LBA_BITS+:LBA_BITS]};
assign video_wav_lba={{(32-LBA_BITS){1'b0}},soundtrack_lbas_table[program_select*LBA_BITS+:LBA_BITS]};
assign video_size=clip_file(program_select);assign video_wav_size=clip_wav(program_select);

genvar image_slot;
generate for(image_slot=0;image_slot<9;image_slot=image_slot+1)begin: compact_metadata
 assign image_lbas[image_slot*32+:32]={{(32-LBA_BITS){1'b0}},image_lbas_compact[image_slot*LBA_BITS+:LBA_BITS]};
 assign image_sizes[image_slot*32+:32]={5'd0,image_sizes_compact[image_slot*27+:27]};
end endgenerate

assign sd_sec_read_addr=32'd0;
assign image_count=done?bmp_count:4'd0;

always @(posedge clk) begin
    if(!rst && state==READ && sd_sec_read_data_valid && byte_count<512)
        index_bytes[byte_count[8:0]]<=sd_sec_read_data;
    ram_q<=index_bytes[{word_index,byte_lane}];
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        image_lookup_slot<=0;image_lookup_lba<=0;image_lookup_size<=0;image_lookup_valid<=0;lookup_mode<=0;lookup_slot<=0;
        state<=IDLE;fetch_context<=HEADER_WORD;byte_count<=0;timer<=0;reserved_bad<=0;
        word_index<=0;entry_base<=8;scan_word<=9;byte_lane<=0;word_value<=0;
        field<=0;entry_idx<=0;entry_count<=0;bmp_count<=0;prior_idx<=0;
        current_kind<=0;kind_bad<=0;entry_nonzero<=0;current_reserved_bad<=0;
        current_lba<=0;current_size<=0;current_sectors<=0;current_id<=0;
        current_end<=0;expected_sectors<=0;prior_lba<=0;prior_end<=0;
        entry_bad<=0;overlap_bad<=0;
        sd_sec_read<=0;done<=0;failed<=0;error_code<=0;
        image_entry_positions<=0;image_lbas_compact<=0;image_sizes_compact<=0;image_types<=0;image_sectors<=0;image_ids<=0;
        wav_present<=0;wav_lba<=0;wav_size<=0;
        video_lbas_table<=0;soundtrack_lbas_table<=0;video_seen<=0;soundtrack_seen<=0;

    end else case(state)
    IDLE: if(start && sd_init_done) begin state<=READ;sd_sec_read<=1;timer<=0;end
    READ: begin
        timer<=timer+1'b1;
        if(sd_sec_read_data_valid) begin
            if(byte_count>=416 && sd_sec_read_data!=0)reserved_bad<=1;
            if(byte_count<513)byte_count<=byte_count+1'b1;
        end
        if(sd_sec_read_end) begin
            sd_sec_read<=0;
            if(byte_count!=512 || sd_sec_read_data_valid)begin error_code<=6;state<=ERROR;end
            else begin fetch_context<=HEADER_WORD;field<=0;word_index<=0;byte_lane<=0;state<=RAM_WAIT;end
        end else if(timer>=TIMEOUT_CYCLES-1)begin sd_sec_read<=0;error_code<=6;state<=ERROR;end
    end
    RAM_WAIT: state<=RAM_BYTE;
    RAM_BYTE: begin
        word_value<={ram_q,word_value[31:8]};
        if(byte_lane==3)begin byte_lane<=0;state<=WORD_READY;end
        else begin byte_lane<=byte_lane+1'b1;state<=RAM_WAIT;end
    end
    WORD_READY: case(fetch_context)
        HEADER_WORD: begin

            if(field==0 && word_value!=32'h474d4946)begin error_code<=1;state<=ERROR;end
            else if(field==1 && word_value[15:0]!=1)begin error_code<=2;state<=ERROR;end
            else if(field==1 && (word_value[31:16]<1 || word_value[31:16]>16))begin error_code<=3;state<=ERROR;end
            else if((field==2 && word_value!=32) || (field==3 && word_value!=2048) ||
                    (field>=5 && word_value!=0) || (field==7 && reserved_bad))begin error_code<=4;state<=ERROR;end
            else begin
                if(field==1)entry_count<=word_value[20:16];
                if(field==7) begin
                    fetch_context<=ENTRY_WORD;field<=0;word_index<=8;entry_idx<=0;entry_base<=8;entry_nonzero<=0;
                end else begin field<=field+1'b1;word_index<=word_index+1'b1;end
                state<=RAM_WAIT;
            end
        end
        ENTRY_WORD: begin
            entry_nonzero<=entry_nonzero || (word_value!=0);
            case(field)
                0:begin current_kind<=word_value[1:0];kind_bad<=word_value<1 || word_value>3;end
                1:current_lba<=word_value;
                2:current_size<=word_value;
                3:current_sectors<=word_value;
                4:current_id<=word_value;
                5:current_reserved_bad<=word_value!=0;
            endcase
            if(field==5)state<=CALCULATE;
            else begin field<=field+1'b1;word_index<=word_index+1'b1;state<=RAM_WAIT;end
        end
        PRIOR_LBA: begin
            if(lookup_mode)begin image_lookup_lba<=word_value;word_index<=word_index+1;end
            else begin prior_lba<=word_value[LBA_BITS-1:0];word_index<=word_index+2;end
            fetch_context<=PRIOR_SECTORS;state<=RAM_WAIT;
        end
        PRIOR_SECTORS: begin
            if(lookup_mode)begin image_lookup_size<=word_value;image_lookup_slot<=lookup_slot;image_lookup_valid<=1;lookup_mode<=0;state<=FINISH;end
            else begin prior_end<={1'b0,prior_lba}+{1'b0,word_value[LBA_BITS-1:0]};state<=CHECK_OVERLAP;end
        end
        default:state<=ERROR;
    endcase
    CALCULATE: begin
        current_end<={1'b0,current_lba[LBA_BITS-1:0]}+{1'b0,current_sectors[LBA_BITS-1:0]};
        expected_sectors<={9'd0,current_size[31:9]}+(|current_size[8:0]);
        state<=CHECK_ENTRY;
    end
    CHECK_ENTRY: begin
        entry_bad<=kind_bad || (|current_lba[31:LBA_BITS]) || (|current_sectors[31:LBA_BITS]) || current_lba<2048 || current_end>MAX_LBA ||
            current_size==0 || current_size>32'd134217728 || current_sectors!=expected_sectors ||
            (current_kind==1 && (current_size<54 || bmp_count>=9)) ||
            (current_kind==2 && (current_size<44 || current_id<1 || current_id>4 ||
                (current_id==1 && wav_present) || (current_id>=2 && current_id<=4 && (soundtrack_seen[soundtrack_slot] || current_size!=clip_wav(soundtrack_slot))))) ||
            (current_kind==3 && (current_id<1 || current_id>3 || current_size!=clip_file(video_slot) || video_seen[video_slot])) || current_reserved_bad;
        state<=ENTRY_RESULT;
    end
    ENTRY_RESULT: begin
        if(entry_idx>=entry_count) begin
            if(entry_nonzero)begin error_code<=4;state<=ERROR;end else state<=NEXT_ENTRY;
        end else if(entry_bad)begin error_code<=5;state<=ERROR;end
        else if(entry_idx==0)state<=COMMIT;
        else begin prior_idx<=0;scan_word<=9;word_index<=9;fetch_context<=PRIOR_LBA;state<=RAM_WAIT;end
    end
    CHECK_OVERLAP: begin
        overlap_bad<=({1'b0,current_lba[LBA_BITS-1:0]}<prior_end) && ({1'b0,prior_lba}<current_end);
        state<=OVERLAP_RESULT;
    end
    OVERLAP_RESULT: begin
        if(overlap_bad)begin error_code<=5;state<=ERROR;end
        else if(prior_idx+1'b1==entry_idx)state<=COMMIT;
        else begin
            prior_idx<=prior_idx+1'b1;scan_word<=scan_word+6;word_index<=scan_word+6;
            fetch_context<=PRIOR_LBA;state<=RAM_WAIT;
        end
    end
    COMMIT: begin
        if(current_kind==1)begin
            image_entry_positions[bmp_count*4+:4]<=entry_idx;
            image_lbas_compact[bmp_count*LBA_BITS+:LBA_BITS]<=current_lba[LBA_BITS-1:0];
            image_sizes_compact[bmp_count*27+:27]<=current_size[26:0];
            image_types[bmp_count*32+:32]<=32'd1;
            image_sectors[bmp_count*32+:32]<=current_sectors;
            image_ids[bmp_count*32+:32]<=current_id;
            bmp_count<=bmp_count+1'b1;
        end else if(current_kind==2)begin
            if(current_id==1)begin wav_present<=1;wav_lba<=current_lba;wav_size<=current_size;end
            else begin soundtrack_seen[soundtrack_slot]<=1;soundtrack_lbas_table[soundtrack_slot*LBA_BITS+:LBA_BITS]<=current_lba[LBA_BITS-1:0];end
        end else begin video_seen[video_slot]<=1;video_lbas_table[video_slot*LBA_BITS+:LBA_BITS]<=current_lba[LBA_BITS-1:0];end
        state<=NEXT_ENTRY;
    end
    NEXT_ENTRY: begin
        if(entry_idx==15)state<=FINISH;
        else begin
            entry_idx<=entry_idx+1'b1;entry_base<=entry_base+6;word_index<=entry_base+6;
            field<=0;entry_nonzero<=0;fetch_context<=ENTRY_WORD;state<=RAM_WAIT;
        end
    end
    FINISH:begin
      if(!done && (video_seen!=soundtrack_seen || (video_seen!=0 && video_seen!=3'b111)))begin error_code<=5;state<=ERROR;end
      else begin
       done<=1;
       if(image_select>=bmp_count)image_lookup_valid<=0;
       else if(!image_lookup_valid || image_lookup_slot!=image_select)begin
        lookup_mode<=1;lookup_slot<=image_select;image_lookup_valid<=0;
        word_index<=9+image_entry_positions[image_select*4+:4]*6;byte_lane<=0;fetch_context<=PRIOR_LBA;state<=RAM_WAIT;
       end
      end
    end
    ERROR:begin failed<=1;sd_sec_read<=0;end
    default:state<=ERROR;
    endcase
end
endmodule
