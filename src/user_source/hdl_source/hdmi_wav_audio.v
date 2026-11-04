module hdmi_wav_audio #(
    parameter integer PIXEL_HZ=25_000_000,
    parameter integer SAMPLE_HZ=48_000,
    parameter integer FIFO_ADDR_BITS=12,
    parameter integer PREFILL_FRAMES=2048
)(
    input clk,input rst,input source_ready_async,
    input [31:0] fifo_data,input fifo_empty,input [FIFO_ADDR_BITS-1:0] fifo_used,
    output fifo_read,output reg audio_valid,output reg [23:0] audio_left,output reg [23:0] audio_right,
    output reg acr_valid,output [19:0] acr_n,output [19:0] acr_cts,
    (* preserve = "true", keep = "true" *) output reg [31:0] underflow_count,
    output reg playing,output quiescent
);
reg [1:0] ready_sync;
reg [24:0] accumulator;
wire [24:0] sample_sum=accumulator+SAMPLE_HZ;
wire sample_tick=sample_sum>=PIXEL_HZ;
reg [14:0] acr_count;
assign fifo_read=sample_tick && playing && ready_sync[1] && !fifo_empty;
assign quiescent=!ready_sync[1] && !playing;
assign acr_n=20'd6144;
assign acr_cts=20'd25000;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  ready_sync<=0;accumulator<=0;acr_count<=0;audio_valid<=0;audio_left<=0;audio_right<=0;
  acr_valid<=0;underflow_count<=0;playing<=0;
 end else begin
  ready_sync<={ready_sync[0],source_ready_async};audio_valid<=0;acr_valid<=0;
  if(acr_count==24999) begin acr_count<=0;acr_valid<=1;end else acr_count<=acr_count+1'b1;
  if(!ready_sync[1]) playing<=0;
  else if(!playing && fifo_used>=PREFILL_FRAMES) playing<=1;
  if(sample_tick) begin
   accumulator<=sample_sum-PIXEL_HZ;audio_valid<=1;
   audio_left<=0;audio_right<=0;
   if(playing && ready_sync[1]) begin
    if(fifo_empty) begin underflow_count<=underflow_count+1'b1;playing<=0;end
    else begin audio_left<={fifo_data[15:0],8'd0};audio_right<={fifo_data[31:16],8'd0};end
   end
  end else accumulator<=sample_sum;
 end
end
endmodule
