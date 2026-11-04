module bmp_read # (parameter integer TIMEOUT_CYCLES=100_000_000)(
 input clk,input rst,output ready,
 input load_start,input load_abort,input [31:0] load_sector,input [31:0] load_size,
 output reg load_done,output reg load_failed,
 input sd_init_done,output reg [3:0] state_code,
 input [15:0] bmp_width,input [15:0] bmp_height,
 output reg write_req,input write_req_ack,
 output reg sd_sec_read,output reg [31:0] sd_sec_read_addr,
 input [7:0] sd_sec_read_data,input sd_sec_read_data_valid,input sd_sec_read_end,
 input pixel_sector_ready,output load_data_active,
 output reg bmp_data_wr_en,output reg [23:0] bmp_data,input pixel_ready,
 output reg [12:0] source_width,output reg [12:0] source_height,output reg dimensions_valid);
localparam IDLE=0,HDR=1,CALCULATE=2,CHECK=3,WAIT_WRITE=4,REQUEST=5,RECEIVE=6,DRAIN_WAIT=7,DRAIN_BYTE=8,PIXEL=9,ERROR=10;
reg [3:0] state;
reg [31:0] file_len,pixel_offset,dib_size,width,height,compression,reserved,image_bytes,expected_size,base_lba;
reg [15:0] signature,planes,bit_count;
reg [13:0] stride,row_bytes,row_byte;
reg [25:0] pixel_bytes;reg [32:0] pixel_end;
reg [31:0] file_position,timer;
reg [9:0] sector_bytes,drain_index;
reg [1:0] byte_lane;
(* ram_style="block" *) reg [7:0] sector_ram[0:511];reg [7:0] byte_q;
wire [31:0] calculated_stride=(width*3+3)&32'hfffffffc;
assign ready=state==IDLE;
assign load_data_active=state>=REQUEST && state<=PIXEL;
always @(posedge clk)begin
 if(state==RECEIVE && sd_sec_read_data_valid && sector_bytes<512)sector_ram[sector_bytes[8:0]]<=sd_sec_read_data;
 byte_q<=sector_ram[drain_index[8:0]];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=IDLE;load_done<=0;load_failed<=0;state_code<=0;write_req<=0;
  sd_sec_read<=0;sd_sec_read_addr<=0;file_len<=0;pixel_offset<=0;dib_size<=0;width<=0;height<=0;
  compression<=0;reserved<=0;image_bytes<=0;signature<=0;planes<=0;bit_count<=0;
  expected_size<=0;base_lba<=0;stride<=0;row_bytes<=0;row_byte<=0;pixel_bytes<=0;pixel_end<=0;
  file_position<=0;sector_bytes<=0;drain_index<=0;byte_lane<=0;bmp_data_wr_en<=0;bmp_data<=0;
  source_width<=0;source_height<=0;dimensions_valid<=0;timer<=0;
 end else if(load_abort)begin
  state<=ERROR;load_failed<=1;load_done<=0;state_code<=8;sd_sec_read<=0;write_req<=0;bmp_data_wr_en<=0;
 end else begin
  case(state)
   IDLE:begin
    state_code<=1;sd_sec_read<=0;write_req<=0;
    if(load_start && sd_init_done)begin
     expected_size<=load_size;base_lba<=load_sector;sd_sec_read_addr<=load_sector;sd_sec_read<=1;
     load_done<=0;load_failed<=0;dimensions_valid<=0;sector_bytes<=0;timer<=0;state<=HDR;
     signature<=0;file_len<=0;pixel_offset<=0;dib_size<=0;width<=0;height<=0;
     compression<=0;reserved<=0;image_bytes<=0;planes<=0;bit_count<=0;
    end
   end
   HDR:begin
    state_code<=2;timer<=timer+1'b1;
    if(sd_sec_read_data_valid)begin
     if(sector_bytes<513)sector_bytes<=sector_bytes+1'b1;
     case(sector_bytes)
       0:signature[7:0]<=sd_sec_read_data;1:signature[15:8]<=sd_sec_read_data;
       2:file_len[7:0]<=sd_sec_read_data;3:file_len[15:8]<=sd_sec_read_data;4:file_len[23:16]<=sd_sec_read_data;5:file_len[31:24]<=sd_sec_read_data;
       6:reserved[7:0]<=sd_sec_read_data;7:reserved[15:8]<=sd_sec_read_data;8:reserved[23:16]<=sd_sec_read_data;9:reserved[31:24]<=sd_sec_read_data;
       10:pixel_offset[7:0]<=sd_sec_read_data;11:pixel_offset[15:8]<=sd_sec_read_data;12:pixel_offset[23:16]<=sd_sec_read_data;13:pixel_offset[31:24]<=sd_sec_read_data;
       14:dib_size[7:0]<=sd_sec_read_data;15:dib_size[15:8]<=sd_sec_read_data;16:dib_size[23:16]<=sd_sec_read_data;17:dib_size[31:24]<=sd_sec_read_data;
       18:width[7:0]<=sd_sec_read_data;19:width[15:8]<=sd_sec_read_data;20:width[23:16]<=sd_sec_read_data;21:width[31:24]<=sd_sec_read_data;
       22:height[7:0]<=sd_sec_read_data;23:height[15:8]<=sd_sec_read_data;24:height[23:16]<=sd_sec_read_data;25:height[31:24]<=sd_sec_read_data;
       26:planes[7:0]<=sd_sec_read_data;27:planes[15:8]<=sd_sec_read_data;
       28:bit_count[7:0]<=sd_sec_read_data;29:bit_count[15:8]<=sd_sec_read_data;
       30:compression[7:0]<=sd_sec_read_data;31:compression[15:8]<=sd_sec_read_data;32:compression[23:16]<=sd_sec_read_data;33:compression[31:24]<=sd_sec_read_data;
       34:image_bytes[7:0]<=sd_sec_read_data;35:image_bytes[15:8]<=sd_sec_read_data;36:image_bytes[23:16]<=sd_sec_read_data;37:image_bytes[31:24]<=sd_sec_read_data;
     endcase
    end
    if(sd_sec_read_end)begin
     sd_sec_read<=0;
     if(sector_bytes!=512 || sd_sec_read_data_valid)state<=ERROR;else state<=CALCULATE;
    end else if(timer>=TIMEOUT_CYCLES-1)state<=ERROR;
   end
   CALCULATE:begin

    if(width<1 || width>4096 || height<1 || height>4096)state<=ERROR;
    else begin
     row_bytes<=width[12:0]*14'd3;stride<=calculated_stride[13:0];
     pixel_bytes<=calculated_stride[13:0]*height[12:0];
     state<=CHECK;
    end
   end
   CHECK:begin
    if(signature!=16'h4d42 || dib_size!=40 || planes!=1 || bit_count!=24 || compression!=0 || reserved!=0 ||
       pixel_offset<54 || pixel_offset>4096 || file_len!=expected_size ||
       {1'b0,pixel_offset}+{7'd0,pixel_bytes}>{1'b0,file_len} ||
       (image_bytes!=0 && image_bytes!={6'd0,pixel_bytes}))state<=ERROR;
    else begin
     source_width<=width[12:0];source_height<=height[12:0];dimensions_valid<=1;
     pixel_end<={1'b0,pixel_offset}+{7'd0,pixel_bytes};file_position<=0;row_byte<=0;byte_lane<=0;
     write_req<=1;sd_sec_read_addr<=base_lba;state<=WAIT_WRITE;
    end
   end
   WAIT_WRITE:begin state_code<=3;if(write_req_ack)begin write_req<=0;state<=REQUEST;end end
   REQUEST:begin
    state_code<=4;
    if(pixel_sector_ready)begin sd_sec_read<=1;sector_bytes<=0;timer<=0;state<=RECEIVE;end
   end
   RECEIVE:begin
    timer<=timer+1'b1;
    if(sd_sec_read_data_valid && sector_bytes<513)sector_bytes<=sector_bytes+1'b1;
    if(sd_sec_read_end)begin
     sd_sec_read<=0;
     if(sector_bytes!=512 || sd_sec_read_data_valid)state<=ERROR;
     else begin drain_index<=0;state<=DRAIN_WAIT;end
    end else if(timer>=TIMEOUT_CYCLES-1)state<=ERROR;
   end
   DRAIN_WAIT:begin
    if(drain_index==512)begin
     if(file_position>=expected_size)begin load_done<=1;state<=IDLE;end
     else begin sd_sec_read_addr<=sd_sec_read_addr+1'b1;state<=REQUEST;end
    end else state<=DRAIN_BYTE;
   end
   DRAIN_BYTE:begin
    drain_index<=drain_index+1'b1;file_position<=file_position+1'b1;state<=DRAIN_WAIT;
    if(file_position>=pixel_offset && {1'b0,file_position}<pixel_end)begin
     if(row_byte==stride-1'b1)row_byte<=0;else row_byte<=row_byte+1'b1;
     if(row_byte<row_bytes)begin
      case(byte_lane)
       0:begin bmp_data[7:0]<=byte_q;byte_lane<=1;end
       1:begin bmp_data[15:8]<=byte_q;byte_lane<=2;end
       2:begin bmp_data[23:16]<=byte_q;byte_lane<=0;bmp_data_wr_en<=1;state<=PIXEL;end
      endcase
     end
    end
   end
   PIXEL:if(pixel_ready)begin bmp_data_wr_en<=0;state<=DRAIN_WAIT;end
   ERROR:begin state_code<=8;load_failed<=1;load_done<=0;sd_sec_read<=0;write_req<=0;bmp_data_wr_en<=0;end
   default:state<=ERROR;
  endcase
 end
end
endmodule
