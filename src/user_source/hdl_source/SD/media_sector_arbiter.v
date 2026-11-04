module media_sector_arbiter #(
    parameter integer VOICE_ENABLE=0,
    parameter integer TIMEOUT_CYCLES=500_000,
    parameter integer FIFO_ADDR_BITS=12,
    parameter integer LOW_WATER=2048,
    parameter integer HIGH_WATER=3072
)(
    input clk,input rst,input initialized,input index_done,
    input index_req,input [31:0] index_addr,output index_valid,output index_end,
    input audio_req,input [31:0] audio_addr,output audio_valid,output audio_end,output reg audio_error,
    input bmp_req,input [31:0] bmp_addr,output bmp_valid,output bmp_end,output reg bmp_error,
    input video_req,input [31:0] video_addr,output video_valid,output video_end,output reg video_error,
    input voice_req,input[31:0]voice_addr,output voice_valid,voice_end,output reg voice_error,
    input [FIFO_ADDR_BITS-1:0] fifo_level,
    output reg sd_req,output reg [31:0] sd_addr,input sd_valid,input sd_end,
    output reg transport_failed,output [2:0] active_owner,
    (* preserve = "true", keep = "true" *) output reg [31:0] max_sector_cycles,
    (* preserve = "true", keep = "true" *) output reg [31:0] audio_sectors,
    (* preserve = "true", keep = "true" *) output reg [31:0] bmp_sectors
);
localparam IDLE=0,ACTIVE=1,GAP0=2,GAP1=3,FAILED=4;
localparam INDEX=1,AUDIO=2,BMP=3,VIDEO=4,VOICE=5;
reg [2:0] state;
reg [2:0] owner;
reg [31:0] timer;
reg audio_urgent;
wire timeout_now=(state==ACTIVE && !sd_end && timer>=TIMEOUT_CYCLES-1);
assign voice_valid=state==ACTIVE&&owner==VOICE&&sd_valid;
assign voice_end=state==ACTIVE&&owner==VOICE&&sd_end;
assign active_owner=(state==ACTIVE)?owner:3'd0;
assign index_valid=state==ACTIVE && owner==INDEX && sd_valid;
assign index_end=(state==ACTIVE && owner==INDEX && sd_end) || (timeout_now && owner==INDEX);
assign audio_valid=state==ACTIVE && owner==AUDIO && sd_valid;
assign audio_end=state==ACTIVE && owner==AUDIO && sd_end;
assign video_valid=state==ACTIVE && owner==VIDEO && sd_valid;
assign video_end=state==ACTIVE && owner==VIDEO && sd_end;
assign bmp_valid=state==ACTIVE && owner==BMP && sd_valid;
assign bmp_end=state==ACTIVE && owner==BMP && sd_end;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  state<=IDLE;owner<=0;timer<=0;audio_urgent<=1;sd_req<=0;sd_addr<=0;
  transport_failed<=0;voice_error<=0;audio_error<=0;bmp_error<=0;video_error<=0;max_sector_cycles<=0;audio_sectors<=0;bmp_sectors<=0;
 end else begin
  voice_error<=0;audio_error<=0;bmp_error<=0;video_error<=0;
  if(fifo_level<LOW_WATER) audio_urgent<=1;
  else if(fifo_level>=HIGH_WATER) audio_urgent<=0;
  case(state)
  IDLE: begin
   timer<=0;sd_req<=0;
   if(initialized) begin
    if(!index_done && index_req) begin owner<=INDEX;sd_addr<=index_addr;sd_req<=1;state<=ACTIVE;end
    else if(index_done) begin
     if(audio_req && (audio_urgent || (!bmp_req && !video_req && (!VOICE_ENABLE || !voice_req)))) begin owner<=AUDIO;sd_addr<=audio_addr;sd_req<=1;state<=ACTIVE;end
     else if(VOICE_ENABLE && voice_req)begin owner<=VOICE;sd_addr<=voice_addr;sd_req<=1;state<=ACTIVE;end
     else if(video_req) begin owner<=VIDEO;sd_addr<=video_addr;sd_req<=1;state<=ACTIVE;end
     else if(bmp_req) begin owner<=BMP;sd_addr<=bmp_addr;sd_req<=1;state<=ACTIVE;end
    end
   end
  end
  ACTIVE: begin
   timer<=timer+1'b1;
   if(sd_end) begin
    sd_req<=0;state<=GAP0;
    if(timer>max_sector_cycles) max_sector_cycles<=timer;
    if(owner==AUDIO) audio_sectors<=audio_sectors+1'b1;
    if(owner==BMP) bmp_sectors<=bmp_sectors+1'b1;
   end else if(timeout_now) begin

    sd_req<=0;transport_failed<=1;state<=FAILED;
    voice_error<=1;audio_error<=1;bmp_error<=1;video_error<=1;
   end
  end
  GAP0:state<=GAP1;
  GAP1:state<=IDLE;
  FAILED:sd_req<=0;
  default:state<=FAILED;
  endcase
 end
end
endmodule
