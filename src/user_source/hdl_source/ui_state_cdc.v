module ui_state_cdc #(parameter WIDTH=124)(input sclk,srst,input source_vs,input [WIDTH-1:0] source_state,
 input dclk,drst,input install_frame,output reg [WIDTH-1:0] active_state);
(* preserve="true" *)reg [WIDTH-1:0] held;
(* preserve="true" *)reg req,ack;
(* async_reg="true",preserve="true",keep="true" *)reg [1:0] ack_sync,req_sync;
reg pv;reg [6:0] settling;reg seen,guard;reg [WIDTH-1:0] pending;
always @(posedge sclk or posedge srst)begin
 if(srst)begin held<=0;req<=0;ack_sync<=0;pv<=1;settling<=0;end
 else begin
  ack_sync<={ack_sync[0],ack};pv<=source_vs;
  if(pv && !source_vs)settling<=1;
  else if(settling!=0)begin
   if(settling==64)begin
    if(ack_sync[1]==req)begin held<=source_state;req<=~req;settling<=0;end
   end else settling<=settling+1'b1;
  end
 end
end
always @(posedge dclk or posedge drst)begin
 if(drst)begin req_sync<=0;seen<=0;guard<=0;ack<=0;pending<=0;active_state<=0;end
 else begin
  req_sync<={req_sync[0],req};
  if(req_sync[1]!=seen && !guard)guard<=1;
  else if(guard)begin pending<=held;seen<=req_sync[1];ack<=req_sync[1];guard<=0;end
  if(install_frame)active_state<=pending;
 end
end
endmodule
