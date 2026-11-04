module eco_visual_transition #(parameter RADAR_ENABLE=1,RADAR_STYLE=1)(
 input clk,input rst,input [1:0] scene_mode,input request_eco,input presence,
 input [23:0] in_rgb,input in_de,in_hs,in_vs,
 output standby,output engaged,output [6:0] audio_gain,
 output [1:0] state_debug,output [5:0] depth_debug,
 output reg [23:0] out_rgb,output reg out_de,out_hs,out_vs);
localparam NORMAL=2'd0,SHUTDOWN=2'd1,STANDBY=2'd2,WAKEUP=2'd3;
reg [1:0] state;
reg [5:0] depth;
reg [6:0] radar_phase;
reg previous_vs,previous_de;
reg [9:0] x;reg [8:0] y;
wire tick=previous_vs && !in_vs;
wire normal_scene=scene_mode==0;
assign standby=normal_scene && state==STANDBY;
assign engaged=normal_scene && state!=NORMAL;
assign state_debug=state;assign depth_debug=depth;
assign audio_gain=(!normal_scene || state==NORMAL)?7'd64:
                  (state==STANDBY || depth>=32)?7'd0:(7'd64-{depth,1'b0});
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=NORMAL;depth<=0;radar_phase<=0;previous_vs<=0;previous_de<=0;x<=0;y<=0;end
 else begin
  previous_vs<=in_vs;previous_de<=in_de;
  if(tick)begin x<=0;y<=0;end
  else begin
   if(in_de)x<=x+1'b1;else x<=0;
   if(previous_de && !in_de && y<360)y<=y+1'b1;
  end

  if(!normal_scene)begin state<=NORMAL;depth<=0;radar_phase<=0;end
  else if(tick)case(state)
   NORMAL:if(request_eco && !presence)begin state<=SHUTDOWN;depth<=0;end
   SHUTDOWN:begin
    if(presence)begin state<=WAKEUP;if(depth>1)depth<=depth-2'd2;else depth<=0;end
    else if(depth==41)begin state<=STANDBY;depth<=42;radar_phase<=0;end
    else depth<=depth+1'b1;
   end
   STANDBY:begin
    radar_phase<=radar_phase+1'b1;
    if(presence)begin state<=WAKEUP;depth<=40;radar_phase<=0;end
   end
   WAKEUP:begin

    if(depth<=2)begin state<=NORMAL;depth<=0;end
    else depth<=depth-2'd2;
   end
  endcase
 end
end
wire anim=normal_scene && (state==SHUTDOWN || state==WAKEUP);
wire [8:0] dx=x>=395?x-10'd395:10'd395-x;
wire [8:0] dy=y>=180?y-9'd180:9'd180-y;
wire [8:0] radar_dy=y>=180?y-9'd180:9'd180-y;
wire [8:0] half_height=(6'd32-depth)*9'd6;
wire [8:0] line_width=(6'd40-depth)*9'd31;
wire window_pixel=depth<32 && dy<half_height;
wire line_pixel=depth>=32 && depth<=40 && dy==0 && dx<=line_width;
wire dot_pixel=depth==41 && dy==0 && dx==0;
wire [4:0] shade=depth>=24?5'd4:(5'd16-{1'b0,depth[5:1]});

reg [23:0] rgb0;
reg [4:0] shade0;
reg left0,left1,anim0,anim1,standby0,standby1,window0,window1,line0,line1,dot0,dot1;
reg d0,h0,v0,d1,h1,v1;
(* use_dsp="yes" *) reg [12:0] red1,green1,blue1;
wire [23:0] scaled_rgb={red1[11:4],green1[11:4],blue1[11:4]};
wire radar_hit;wire [23:0] radar_color;

wire [6:0] next_phase=state==STANDBY && !presence?radar_phase+1'b1:radar_phase;
eco_radar_circle #(.STYLE(RADAR_STYLE)) u_circle(.clk(clk),.rst(rst),.frame_tick(tick),.phase(next_phase),.x(x),.y(y),.hit(radar_hit),.color(radar_color),.ready());
always @(posedge clk or posedge rst)begin
 if(rst)begin
  rgb0<=0;shade0<=16;left0<=0;left1<=0;anim0<=0;anim1<=0;standby0<=0;standby1<=0;
  window0<=0;window1<=0;line0<=0;line1<=0;dot0<=0;dot1<=0;
  d0<=0;h0<=0;v0<=0;d1<=0;h1<=0;v1<=0;out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;
  red1<=0;green1<=0;blue1<=0;
 end else begin
  rgb0<=in_rgb;shade0<=anim && x<150?shade:5'd16;left0<=x<150;
  anim0<=anim;standby0<=standby;window0<=window_pixel;line0<=line_pixel;dot0<=dot_pixel;
  d0<=in_de;h0<=in_hs;v0<=in_vs;
  left1<=left0;anim1<=anim0;standby1<=standby0;window1<=window0;line1<=line0;dot1<=dot0;
  red1<=rgb0[23:16]*shade0;green1<=rgb0[15:8]*shade0;blue1<=rgb0[7:0]*shade0;
  d1<=d0;h1<=h0;v1<=v0;
  out_de<=d1;out_hs<=h1;out_vs<=v1;
  if(anim1)begin
   if(left1)out_rgb<=scaled_rgb;
   else if(line1)out_rgb<=24'h91c9d3;
   else if(dot1)out_rgb<=24'h294550;
   else if(window1)out_rgb<=scaled_rgb;
   else out_rgb<=24'h020408;
  end else if(RADAR_ENABLE && standby1 && !left1)begin
   if(radar_hit)out_rgb<=radar_color;
   else out_rgb<=scaled_rgb;
  end else out_rgb<=scaled_rgb;
 end
end
endmodule
