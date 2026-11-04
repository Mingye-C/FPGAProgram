module scene_controller #(parameter integer LONG_FRAMES=90, SENSOR_ENABLE=0)(
 input overload_n,input fire_n,input clk,input rst,input pressed,input video_vs,
 output reg [1:0] scene_mode,output blink,output reg short_event,output reg long_event);
(* async_reg="true" *) reg[1:0] osync,fsync;
reg[2:0] oh,fh;reg overload_active,fire_active;
always @(posedge clk or posedge rst)begin
 if(rst)begin osync<=3;fsync<=3;oh<=7;fh<=7;overload_active<=0;fire_active<=0;end
 else begin osync<={osync[0],overload_n};fsync<={fsync[0],fire_n};
  if(tick)begin
   oh<={oh[1:0],osync[1]};fh<={fh[1:0],fsync[1]};
   if({oh[1:0],osync[1]}==0)overload_active<=1;else if({oh[1:0],osync[1]}==7)overload_active<=0;
   if({fh[1:0],fsync[1]}==0)fire_active<=1;else if({fh[1:0],fsync[1]}==7)fire_active<=0;
  end
 end
end
reg previous,vs_previous,long_sent;reg [6:0] held_frames;reg [1:0] requested;
reg [5:0] blink_frames;
wire tick=vs_previous && !video_vs;
assign blink=blink_frames[5];
always @(posedge clk or posedge rst)begin
 if(rst)begin previous<=0;vs_previous<=0;long_sent<=0;held_frames<=0;requested<=0;scene_mode<=0;blink_frames<=0;short_event<=0;long_event<=0;end
 else begin
  previous<=pressed;vs_previous<=video_vs;short_event<=0;long_event<=0;
  if(!pressed)begin held_frames<=0;long_sent<=0;end
  if(previous && !pressed && !long_sent)begin requested<=requested+1'b1;short_event<=1;end
  if(tick)begin
   blink_frames<=blink_frames+1'b1;
   if(pressed && !long_sent)begin
    if(held_frames>=LONG_FRAMES-1)begin requested<=0;scene_mode<=0;long_sent<=1;long_event<=1;end
    else begin held_frames<=held_frames+1'b1;scene_mode<=requested;end
   end else scene_mode<=requested;
   if(SENSOR_ENABLE && fire_active)scene_mode<=1;else if(SENSOR_ENABLE && overload_active)scene_mode<=2;
  end
 end
end
endmodule
