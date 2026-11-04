module video_stream_reader #(parameter integer SRC_WIDTH=320,SRC_HEIGHT=200,
 parameter integer FRAME_COUNT=239,FRAME_BITS=8,BANK_BITS=2,PROGRAM1_FRAMES=194,PROGRAM2_FRAMES=178,FPS=12)(
 input clk,input rst,input start,input[1:0]program_select,input[31:0]start_lba,input[31:0]file_size,
 input frame_start,input[FRAME_BITS-1:0]frame_index,
 output reg read_req,output reg[31:0]read_addr,
 input[7:0]read_data,input read_valid,input read_end,input read_error,
 output reg header_valid,output reg failed,output reg[3:0]error_code,
 output pixel_valid,output[15:0]pixel_data,input pixel_ready,
 output reg frame_done,output busy);
localparam FRAME_BYTES=SRC_WIDTH*SRC_HEIGHT*2,FRAME_PIXELS=SRC_WIDTH*SRC_HEIGHT,
 MAX_BODY_SECTORS=(FRAME_BYTES+511)/512+1,SLOT_SECTORS=MAX_BODY_SECTORS+1,
 STRIDE=SLOT_SECTORS*512,OFFSET_BITS=$clog2(FRAME_COUNT*SLOT_SECTORS),
 PIXEL_BITS=$clog2(FRAME_PIXELS+1),BYTE_BITS=$clog2(FRAME_BYTES+17);
localparam IDLE=0,HEADER=1,CHECK=2,READY=3,READ=4,WAIT_BANK=5,ERROR=6,FHEADER=7,FCHECK=8;
localparam TOKEN=0,COLOR=1,RUN=2,LITERAL=3;
reg[3:0]state;reg header_bad,reserved_bad,frame_bad;
reg[31:0]base;reg[9:0]count;reg[7:0]low_byte;
reg[$clog2(MAX_BODY_SECTORS)-1:0]sector,body_sectors;
localparam BANK_COUNT=1<<BANK_BITS;
reg[BANK_BITS-1:0]producer_bank,consumer_bank;reg[BANK_COUNT-1:0]bank_full;
reg frame_active,producer_finished,word_valid;
reg[7:0]pointer;reg[PIXEL_BITS-1:0]consumed;
(* ram_style="bram_9k" *)reg[15:0]sector_ram[0:BANK_COUNT*256-1];reg[15:0]word_q;
reg[31:0]encoded_bytes;reg[BYTE_BITS-2:0]words_used;
reg[1:0]decode_state;reg[14:0]packet_left;reg[15:0]run_color;
wire[FRAME_BITS-1:0]selected_frames=program_select==0?FRAME_COUNT:program_select==1?PROGRAM1_FRAMES:PROGRAM2_FRAMES;
wire[31:0]selected_file=512+selected_frames*STRIDE;
wire[31:0]selected_data=selected_frames*FRAME_BYTES;
wire[OFFSET_BITS-1:0]fn=frame_index;
wire[OFFSET_BITS-1:0]frame_offset=fn*SLOT_SECTORS;
reg[31:0]expected_header_word;
always @*case(count[5:2])
 0:expected_header_word=32'h57415256;
 1,6:expected_header_word=2;
 2:expected_header_word=SRC_WIDTH;
 3:expected_header_word=SRC_HEIGHT;
 4:expected_header_word=FPS;
 5:expected_header_word=selected_frames;
 7:expected_header_word=selected_data;
 8:expected_header_word=FRAME_BYTES;
 9:expected_header_word=1;
 default:expected_header_word=0;
endcase
wire[31:0]expected_frame_word=count<4?32'h314c5246:count<8?{{(32-FRAME_BITS){1'b0}},frame_index}:FRAME_PIXELS;
assign pixel_valid=frame_active && !failed && (decode_state==RUN || (decode_state==LITERAL && word_valid));
assign pixel_data=decode_state==RUN?run_color:word_q;
assign busy=state!=IDLE && (state!=READY || frame_active);
wire word_ready=decode_state==TOKEN || decode_state==COLOR || (decode_state==LITERAL && pixel_ready);
wire word_take=frame_active && word_valid && word_ready;
wire pixel_take=pixel_valid && pixel_ready;
always @(posedge clk)begin
 if(state==READ && read_valid && count<512 && count[0])sector_ram[{producer_bank,count[8:1]}]<={read_data,low_byte};
 word_q<=sector_ram[{consumer_bank,pointer}];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=IDLE;read_req<=0;read_addr<=0;base<=0;count<=0;low_byte<=0;sector<=0;body_sectors<=0;
  header_valid<=0;failed<=0;error_code<=0;frame_done<=0;header_bad<=0;reserved_bad<=0;frame_bad<=0;
  producer_bank<=0;consumer_bank<=0;bank_full<=0;frame_active<=0;producer_finished<=0;
  word_valid<=0;pointer<=0;consumed<=0;encoded_bytes<=0;words_used<=0;
  decode_state<=TOKEN;packet_left<=0;run_color<=0;
 end else if(read_error)begin state<=ERROR;read_req<=0;failed<=1;header_valid<=0;error_code<=3;word_valid<=0;frame_active<=0;end
 else begin
  case(state)
   IDLE:if(start)begin
    if(file_size!=selected_file || program_select>=3)begin state<=ERROR;error_code<=1;end
    else begin base<=start_lba;read_addr<=start_lba;read_req<=1;count<=0;state<=HEADER;end
   end
   HEADER:begin
    if(read_valid)begin
     if(count<40)begin if(read_data!=expected_header_word[count[1:0]*8+:8])header_bad<=1;end
     else if(read_data!=0)reserved_bad<=1;
     if(count<513)count<=count+1'b1;
    end
    if(read_end)begin read_req<=0;if(count!=512 || read_valid)begin error_code<=2;state<=ERROR;end else state<=CHECK;end
   end
   CHECK:if(header_bad || reserved_bad)begin error_code<=1;state<=ERROR;end else begin header_valid<=1;state<=READY;end
   READY:if(frame_start && !frame_active)begin
    if(frame_index>=selected_frames)begin error_code<=4;state<=ERROR;end
    else begin
     read_addr<=base+1+frame_offset;read_req<=1;count<=0;state<=FHEADER;frame_bad<=0;encoded_bytes<=0;
     producer_bank<=0;consumer_bank<=0;bank_full<=0;pointer<=0;consumed<=0;words_used<=0;
     frame_active<=0;producer_finished<=0;word_valid<=0;frame_done<=0;decode_state<=TOKEN;
    end
   end
   FHEADER:begin
    if(read_valid)begin
     if(count>=8 && count<12)encoded_bytes[count[1:0]*8+:8]<=read_data;
     else if(count<16)begin if(read_data!=expected_frame_word[count[1:0]*8+:8])frame_bad<=1;end
     else if(read_data!=0)frame_bad<=1;
     if(count<513)count<=count+1'b1;
    end
    if(read_end)begin read_req<=0;if(count!=512 || read_valid)begin error_code<=2;state<=ERROR;end else state<=FCHECK;end
   end
   FCHECK:begin
    if(frame_bad || encoded_bytes<4 || encoded_bytes>FRAME_BYTES+16 || encoded_bytes[0])begin error_code<=5;state<=ERROR;end
    else begin
     body_sectors<=(encoded_bytes+511)>>9;sector<=0;count<=0;read_addr<=read_addr+1'b1;
     read_req<=1;state<=READ;frame_active<=1;
    end
   end
   READ:begin
    if(read_valid)begin low_byte<=read_data;if(count<513)count<=count+1'b1;end
    if(read_end)begin
     read_req<=0;
     if(count!=512 || read_valid)begin error_code<=2;state<=ERROR;end
     else begin
      bank_full[producer_bank]<=1;producer_bank<=producer_bank+1'b1;
      if(sector==body_sectors-1'b1)begin producer_finished<=1;state<=READY;end
      else begin sector<=sector+1'b1;state<=WAIT_BANK;end
     end
    end
   end
   WAIT_BANK:if(!bank_full[producer_bank])begin read_addr<=read_addr+1'b1;read_req<=1;count<=0;state<=READ;end
   ERROR:begin failed<=1;header_valid<=0;read_req<=0;word_valid<=0;frame_active<=0;end
   default:state<=ERROR;
  endcase
  if(frame_active && state!=ERROR)begin
   if(word_valid)begin
    if(word_take)begin
     word_valid<=0;words_used<=words_used+1'b1;
     if(words_used>=encoded_bytes[BYTE_BITS-1:1])begin error_code<=5;state<=ERROR;end
     if(pointer==255)begin bank_full[consumer_bank]<=0;consumer_bank<=consumer_bank+1'b1;pointer<=0;end
     else pointer<=pointer+1'b1;
     case(decode_state)
      TOKEN:begin packet_left<=word_q[14:0];decode_state<=word_q[15]?COLOR:LITERAL;end
      COLOR:begin run_color<=word_q;decode_state<=RUN;end
      LITERAL:begin if(packet_left==0)decode_state<=TOKEN;else packet_left<=packet_left-1'b1;end
      default:begin end
     endcase
    end
   end else if(bank_full[consumer_bank])word_valid<=1;
   if(pixel_take)begin
    consumed<=consumed+1'b1;
    if(decode_state==RUN)begin if(packet_left==0)decode_state<=TOKEN;else packet_left<=packet_left-1'b1;end
    if(consumed==FRAME_PIXELS-1)begin
     frame_active<=0;word_valid<=0;bank_full<=0;
     if(packet_left!=0 || !producer_finished || words_used+(decode_state==LITERAL)!=encoded_bytes[BYTE_BITS-1:1])begin error_code<=5;state<=ERROR;end
     else frame_done<=1;
    end
   end
  end
 end
end
endmodule
