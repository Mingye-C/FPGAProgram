module wav_stream_reader #(
    parameter integer FIFO_ADDR_BITS=12,
    parameter integer SECTOR_RESERVE=136
)(
    input clk,input rst,input start,input [31:0] start_lba,input [31:0] file_size,
    output reg read_req,output reg [31:0] read_addr,
    input [7:0] read_data,input read_valid,input read_end,input read_error,
    input [FIFO_ADDR_BITS-1:0] fifo_used,input fifo_full,
    output reg pcm_write,output reg [31:0] pcm_data,
    output reg header_valid,output reg failed,output reg [3:0] error_code,
    output reg [31:0] data_offset,output reg [31:0] data_length,
    (* preserve = "true", keep = "true" *) output reg [31:0] loop_count,
    (* preserve = "true", keep = "true" *) output reg [31:0] overflow_count
);
localparam IDLE=0,HEADER=1,HEADER_GAP=2,PREPARE=3,PAYLOAD=4,ERROR=5;
localparam CHUNK=0,BODY=1,PAD=2,FOUND=3;
reg [2:0] state;
reg [1:0] parser_state;
reg [9:0] sector_bytes;
reg [31:0] file_pos,base_lba,expected_size;
reg [31:0] riff_size,chunk_size;

reg riff_match,wave_match,chunk_data_match,chunk_fmt_match,fmt_match;
reg [2:0] chunk_index;
reg [31:0] body_left,body_index;
reg fmt_seen;
function [7:0] fourcc_byte;
 input [1:0] index;input [31:0] value;
 begin case(index) 0:fourcc_byte=value[7:0];1:fourcc_byte=value[15:8];
 2:fourcc_byte=value[23:16];default:fourcc_byte=value[31:24];endcase end
endfunction
function [7:0] fmt_byte;
 input [3:0] index;
 begin case(index)
 0:fmt_byte=1;2:fmt_byte=2;4:fmt_byte=8'h80;5:fmt_byte=8'hbb;
 9:fmt_byte=8'hee;10:fmt_byte=2;12:fmt_byte=4;14:fmt_byte=16;
 default:fmt_byte=0;endcase end
endfunction
reg [31:0] cursor;
reg [1:0] sample_byte;
reg [23:0] partial_sample;
wire [31:0] completed_size={read_data,chunk_size[23:0]};
wire format_ok=fmt_seen && fmt_match;
wire [31:0] data_end=data_offset+data_length;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  state<=IDLE;parser_state<=CHUNK;read_req<=0;read_addr<=0;sector_bytes<=0;
  file_pos<=0;base_lba<=0;expected_size<=0;riff_size<=0;riff_match<=1;wave_match<=1;
  chunk_data_match<=0;chunk_fmt_match<=0;chunk_size<=0;chunk_index<=0;body_left<=0;body_index<=0;
  fmt_seen<=0;fmt_match<=1;
  cursor<=0;sample_byte<=0;partial_sample<=0;pcm_write<=0;pcm_data<=0;
  header_valid<=0;failed<=0;error_code<=0;data_offset<=0;data_length<=0;loop_count<=0;overflow_count<=0;
 end else begin
  pcm_write<=0;
  if(read_error || failed) begin
   read_req<=0;failed<=1;state<=ERROR;
   if(read_error) error_code<=6;
  end else case(state)
  IDLE: if(start) begin
   if(start_lba<2048 || file_size<44 || file_size>67108864) begin failed<=1;error_code<=3;end
   else begin base_lba<=start_lba;expected_size<=file_size;read_addr<=start_lba;read_req<=1;state<=HEADER;end
  end
  HEADER: begin
   if(read_valid) begin
    sector_bytes<=sector_bytes+1'b1;file_pos<=file_pos+1'b1;
    if(sector_bytes>=512 || (parser_state!=FOUND && (file_pos>=4096 || file_pos>=expected_size))) begin failed<=1;error_code<=3;end
    else if(file_pos<12) begin
     case(file_pos)
      0,1,2,3:riff_match<=riff_match && read_data==fourcc_byte(file_pos[1:0],32'h46464952);
      4,5,6,7:riff_size[(file_pos-4)*8+:8]<=read_data;
      8,9,10,11:wave_match<=wave_match && read_data==fourcc_byte(file_pos[1:0],32'h45564157);
     endcase
    end else case(parser_state)
    CHUNK: begin
     if(chunk_index<4) begin
      chunk_data_match<=(chunk_index==0 || chunk_data_match) && read_data==fourcc_byte(chunk_index[1:0],32'h61746164);
      chunk_fmt_match<=(chunk_index==0 || chunk_fmt_match) && read_data==fourcc_byte(chunk_index[1:0],32'h20746d66);
     end
     else chunk_size[(chunk_index-4)*8+:8]<=read_data;
     if(chunk_index==7) begin
      chunk_index<=0;body_index<=0;body_left<=completed_size;
      if(completed_size>expected_size-file_pos-1) begin failed<=1;error_code<=3;end
      else if(chunk_data_match) begin
       if(!riff_match || !wave_match || riff_size!=expected_size-8) begin failed<=1;error_code<=1;end
       else if(!format_ok) begin failed<=1;error_code<=2;end
       else if(completed_size==0 || completed_size[1:0]!=0 || file_pos+1>4096) begin failed<=1;error_code<=3;end
       else begin data_offset<=file_pos+1;data_length<=completed_size;parser_state<=FOUND;end
      end else if(chunk_fmt_match && (fmt_seen || completed_size<16)) begin failed<=1;error_code<=2;end
      else if(completed_size==0) parser_state<=CHUNK;
      else parser_state<=BODY;
     end else chunk_index<=chunk_index+1'b1;
    end
    BODY: begin
     if(chunk_fmt_match && body_index<16)
      fmt_match<=fmt_match && read_data==fmt_byte(body_index[3:0]);
     body_index<=body_index+1'b1;body_left<=body_left-1'b1;
     if(body_left==1) begin
      if(chunk_fmt_match) fmt_seen<=1;
      parser_state<=chunk_size[0] ? PAD : CHUNK;
     end
    end
    PAD:parser_state<=CHUNK;
    FOUND:begin end
    endcase
   end
   if(read_end) begin
    read_req<=0;sector_bytes<=0;
    if(sector_bytes!=512 || read_valid) begin failed<=1;error_code<=4;end
    else state<=HEADER_GAP;
   end
  end
  HEADER_GAP: begin
   if(parser_state==FOUND) begin
    header_valid<=1;read_addr<=base_lba+(data_offset>>9);
    cursor<={data_offset[31:9],9'd0};state<=PREPARE;
   end else if(file_pos>=4096 || file_pos>=expected_size) begin failed<=1;error_code<=3;end
   else begin read_addr<=read_addr+1'b1;read_req<=1;state<=HEADER;end
  end
  PREPARE: if(fifo_used <= ((1<<FIFO_ADDR_BITS)-1-SECTOR_RESERVE)) begin
   sector_bytes<=0;read_req<=1;state<=PAYLOAD;
  end
  PAYLOAD: begin
   if(read_valid) begin
    sector_bytes<=sector_bytes+1'b1;cursor<=cursor+1'b1;
    if(sector_bytes>=512) begin failed<=1;error_code<=4;end
    if(cursor>=data_offset && cursor<data_end) begin
     case(sample_byte)
      0:partial_sample[7:0]<=read_data;
      1:partial_sample[15:8]<=read_data;
      2:partial_sample[23:16]<=read_data;
      3:begin
       if(fifo_full) begin overflow_count<=overflow_count+1'b1;failed<=1;error_code<=5;end
       else begin pcm_data<={read_data,partial_sample};pcm_write<=1;end
      end
     endcase
     sample_byte<=sample_byte+1'b1;
    end
   end
   if(read_end) begin
    read_req<=0;sector_bytes<=0;
    if(sector_bytes!=512 || read_valid || (cursor>=data_end && sample_byte!=0)) begin failed<=1;error_code<=4;end
    else begin
     if(cursor>=data_end) begin
      read_addr<=base_lba+(data_offset>>9);cursor<={data_offset[31:9],9'd0};loop_count<=loop_count+1'b1;
     end else read_addr<=read_addr+1'b1;
     state<=PREPARE;
    end
   end
  end
  ERROR:read_req<=0;
  default:begin failed<=1;error_code<=3;end
  endcase
 end
end
endmodule
