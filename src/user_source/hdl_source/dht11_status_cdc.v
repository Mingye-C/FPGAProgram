module dht11_status_cdc(input clk,rst,input update_toggle,input[16:0]held,
 input install_frame,output reg[16:0]active,output ack);
 (*async_reg="true",preserve="true",keep="true"*)reg[1:0]sync;
 reg seen,guard;
 assign ack=seen;
 always @(posedge clk or posedge rst)begin
  if(rst)begin sync<=0;seen<=0;guard<=0;active<=0;end
  else begin
   sync<={sync[0],update_toggle};
   if(sync[1]!=seen && !guard)guard<=1;
   if(install_frame && guard)begin active<=held;seen<=sync[1];guard<=0;end
  end
 end
endmodule
