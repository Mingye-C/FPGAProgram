module hdmi_audio_cdc(input sclk,srst,svalid,input [23:0] sl,sr,
 input dclk,drst,output reg valid,output reg [23:0] left,right,
 output reg acr_valid,output [19:0] acr_n,acr_cts,output reg [31:0] overrun);
(* preserve="true",keep="true" *)reg req,ack;
reg [47:0] held;
(* async_reg="true",preserve="true",keep="true" *)reg [1:0] ack_sync,req_sync;
reg [16:0] acr_count;
assign acr_n=6144;assign acr_cts=74250;
always @(posedge sclk or posedge srst)begin
 if(srst)begin req<=0;ack_sync<=0;held<=0;overrun<=0;end
 else begin ack_sync<={ack_sync[0],ack};
  if(svalid)begin if(req==ack_sync[1])begin held<={sl,sr};req<=~req;end else overrun<=overrun+1'b1;end
 end
end
always @(posedge dclk or posedge drst)begin
 if(drst)begin req_sync<=0;ack<=0;valid<=0;left<=0;right<=0;acr_valid<=0;acr_count<=0;end
 else begin
  req_sync<={req_sync[0],req};valid<=0;acr_valid<=0;
  if(req_sync[1]!=ack)begin left<=held[47:24];right<=held[23:0];valid<=1;ack<=req_sync[1];end
  if(acr_count==74249)begin acr_count<=0;acr_valid<=1;end else acr_count<=acr_count+1'b1;
 end
end
endmodule
