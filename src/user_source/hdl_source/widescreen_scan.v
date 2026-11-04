module widescreen_scan #(parameter HEIGHT=480)(
 input clk,rst,input frame_toggle_async,input line_space,input read_ack,
 output reg read_req,output reg hs,vs,de,output reg [8:0] source_y,
 output reg [31:0] missed_frames);
(* async_reg="true",preserve="true",keep="true" *) reg [1:0] frame_sync;
(* async_reg="true" *) reg [1:0] ack_sync;
reg ack_seen;
reg seen;reg [2:0] state;reg [12:0] count;
localparam IDLE=0,PRE=1,WAIT_LINE=2,LINE=3,GAP=4;
always @(posedge clk or posedge rst)begin
 if(rst)begin ack_sync<=0;ack_seen<=0;frame_sync<=0;seen<=0;state<=IDLE;count<=0;source_y<=0;read_req<=0;hs<=1;vs<=1;de<=0;missed_frames<=0;end
 else begin
  ack_sync<={ack_sync[0],read_ack};
  frame_sync<={frame_sync[0],frame_toggle_async};
  if(ack_sync[1])read_req<=0;
  case(state)
   IDLE:if(frame_sync[1]!=seen)begin seen<=frame_sync[1];source_y<=0;count<=0;vs<=0;read_req<=1;ack_seen<=0;state<=PRE;end
   PRE:begin if(!ack_seen || ack_sync[1])count<=0;
    else if(count!=4095)count<=count+1'b1;if(count==63)vs<=1;
    if(ack_sync[1])ack_seen<=1;
    if(count==4095 && ack_seen && !ack_sync[1])state<=WAIT_LINE;end
   WAIT_LINE:if(line_space)begin de<=1;count<=0;state<=LINE;end
   LINE:if(count==639)begin de<=0;hs<=0;count<=0;state<=GAP;end else count<=count+1'b1;
   GAP:begin
    count<=count+1'b1;if(count==95)hs<=1;
    if(count==159)begin
     if(source_y==HEIGHT-1)state<=IDLE;
     else begin source_y<=source_y+1'b1;state<=WAIT_LINE;end
    end
   end
  endcase
  if(state!=IDLE && frame_sync[1]!=seen)begin

   missed_frames<=missed_frames+1'b1;seen<=frame_sync[1];
  end
 end
end
endmodule
