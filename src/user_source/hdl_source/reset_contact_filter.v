module reset_contact_filter #(parameter SAMPLE_DIV=62500,STABLE_BITS=4)(input clk,input button_n,output reset_n,output sample_tick);
localparam DIV_BITS=$clog2(SAMPLE_DIV);
(* ASYNC_REG="TRUE" *)reg[1:0]sync=2'b11;
reg[DIV_BITS-1:0]divider=0;reg[STABLE_BITS-1:0]count=0;reg stable_n=1'b0;
assign reset_n=stable_n;assign sample_tick=(divider==SAMPLE_DIV-1);
always @(posedge clk)begin
 sync<={sync[0],button_n};if(sample_tick)divider<=0;else divider<=divider+1'b1;
 if(sample_tick)begin
  if(sync[1]==stable_n)count<=0;
  else if(&count)begin stable_n<=sync[1];count<=0;end
  else count<=count+1'b1;
 end
end
endmodule
