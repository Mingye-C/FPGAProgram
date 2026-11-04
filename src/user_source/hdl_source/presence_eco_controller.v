module presence_eco_controller #(
 parameter integer CLOCK_HZ=25000000,
 parameter integer ABSENCE_SECONDS=10,
 parameter integer FILTER_CYCLES=2500
)(input clk,input rst,input presence_async,input [1:0] scene_mode,input video_vs,
 output reg presence_display,output reg eco_active,output presence_filtered);
localparam integer FW=(FILTER_CYCLES<2)?1:$clog2(FILTER_CYCLES);
localparam integer LIMIT=CLOCK_HZ*ABSENCE_SECONDS;
localparam integer TW=(LIMIT<2)?1:$clog2(LIMIT);
(* ASYNC_REG="TRUE" *) reg sync0,sync1;
reg filtered,vs_previous;reg [FW-1:0] stable_count;
reg [TW-1:0] absent_cycles;reg request_eco;
assign presence_filtered=filtered;
wire frame_tick=vs_previous && !video_vs;
always @(posedge clk or posedge rst)begin
 if(rst)begin sync0<=0;sync1<=0;filtered<=0;stable_count<=0;end
 else begin
  sync0<=presence_async;sync1<=sync0;
  if(sync1==filtered)stable_count<=0;
  else if(stable_count==FILTER_CYCLES-1)begin filtered<=sync1;stable_count<=0;end
  else stable_count<=stable_count+1'b1;
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin absent_cycles<=0;request_eco<=0;eco_active<=0;presence_display<=0;vs_previous<=0;end
 else begin
  vs_previous<=video_vs;
  if(scene_mode!=0 || filtered)begin absent_cycles<=0;request_eco<=0;end
  else if(!request_eco)begin
   if(absent_cycles==LIMIT-1)begin request_eco<=1;end
   else absent_cycles<=absent_cycles+1'b1;
  end

  if(scene_mode!=0)begin eco_active<=0;presence_display<=0;end
  else if(frame_tick)begin
   eco_active<=request_eco && !filtered;
   presence_display<=filtered;
  end
 end
end
endmodule
