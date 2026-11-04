module button_event_bank #(parameter EXTERNAL_TICK=0,N=6,DIV=62500,SAMPLES=16)(input clk,rst,input sample_tick,input[N-1:0]buttons_n,output reg[N-1:0]press,release_pulse);
localparam DW=$clog2(DIV),CW=$clog2(SAMPLES);
(* ASYNC_REG="TRUE" *)reg[N-1:0]s0,s1;
reg[N-1:0]stable;reg[DW-1:0]divider;reg[CW-1:0]count[0:N-1];integer i;wire tick=EXTERNAL_TICK?sample_tick:(divider==DIV-1);
always @(posedge clk or posedge rst)begin
 if(rst)begin s0<={N{1'b1}};s1<={N{1'b1}};stable<={N{1'b1}};divider<=0;press<=0;release_pulse<=0;for(i=0;i<N;i=i+1)count[i]<=0;end
 else begin s0<=buttons_n;s1<=s0;press<=0;release_pulse<=0;
 if(!EXTERNAL_TICK)begin if(tick)divider<=0;else divider<=divider+1'b1;end
 if(tick)begin for(i=0;i<N;i=i+1)begin
 if(s1[i]==stable[i])count[i]<=0;
 else if(count[i]==SAMPLES-1)begin stable[i]<=s1[i];count[i]<=0;if(s1[i])release_pulse[i]<=1;else press[i]<=1;end
 else count[i]<=count[i]+1'b1;
 end end
 end end endmodule
