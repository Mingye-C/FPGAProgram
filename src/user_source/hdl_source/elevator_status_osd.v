module elevator_status_osd #(
 parameter integer FLOOR_FRAMES=120,
 parameter SCENE_ENABLE=0,EXTERNAL_FONT_ENABLE=0,ECO_ENABLE=0,NATIVE_TEXT=0,
 parameter integer FIRE_FLOOR_FRAMES=18,
 parameter [23:0] MEDIA_BG=24'h102642,AUDIO_BG=24'h141a34
)(input clk,input rst,
 input [1:0] scene_mode,input scene_blink,input eco_active,
 output native_up,output [4:0] native_slide,output [3:0] current_floor,output [3:0] scene_line_code,output [9:0] raster_x,output [8:0] raster_y,output [23:0] background_p1,
 output [12:0] font_request,input [7:0] external_font_row,
 output [10:0] text_request,input [7:0] external_text,
 input [23:0] in_rgb,input in_de,input in_hs,input in_vs,
 output reg [23:0] out_rgb,output reg out_de,output reg out_hs,output reg out_vs);
wire eco=ECO_ENABLE && eco_active && scene_mode==0;
wire [1:0] scene=SCENE_ENABLE?scene_mode:2'd0;
reg [1:0] scene_previous;
assign native_up=going_up;assign native_slide=slide;assign current_floor=floor_no;assign raster_x=x;assign raster_y=y;assign background_p1=rgb1;
reg [9:0] x;reg [8:0] y;
reg de_prev,vs_prev;
reg [3:0] floor_no,animation_step;
reg going_up;
localparam FCW=(FLOOR_FRAMES<2)?1:$clog2(FLOOR_FRAMES);
reg [FCW-1:0] frame_count;
wire frame_tick=vs_prev && !in_vs;
function [4:0] ease_offset;
 input [3:0] step;
 begin
  case(step)
   0:ease_offset=24;1:ease_offset=20;2:ease_offset=16;3:ease_offset=13;
   4:ease_offset=10;5:ease_offset=8;6:ease_offset=6;7:ease_offset=4;
   8:ease_offset=3;9:ease_offset=2;10,11:ease_offset=1;default:ease_offset=0;
  endcase
 end
endfunction
wire [4:0] slide=ease_offset(animation_step);
wire [9:0] digit_y=(scene==2 || scene==3)?105:going_up ? 10'd105+slide : 10'd105-slide;
wire [9:0] arrow_y=scene==1?10'd200+{6'd0,frame_count[3:0]}:going_up ? 10'd198+slide : 10'd198-slide;
wire [3:0] units=floor_no>=10 ? floor_no-4'd10 : floor_no;
function seven_pixel;
 input [3:0] digit;input [5:0] dx;input [6:0] dy;
 reg [6:0] seg;
 begin

  case(digit)
   0:seg=7'b1111110;1:seg=7'b0110000;2:seg=7'b1101101;
   3:seg=7'b1111001;4:seg=7'b0110011;5:seg=7'b1011011;
   6:seg=7'b1011111;7:seg=7'b1110000;8:seg=7'b1111111;
   9:seg=7'b1111011;10:seg=7'b0001110;11:seg=7'b0000001;default:seg=0;
  endcase
  seven_pixel=(
   (seg[6] && dx>=6 && dx<38 && dy<6) ||
   (seg[5] && dx>=38 && dy>=6 && dy<37) ||
   (seg[4] && dx>=38 && dy>=43 && dy<74) ||
   (seg[3] && dx>=6 && dx<38 && dy>=74) ||
   (seg[2] && dx<6 && dy>=43 && dy<74) ||
   (seg[1] && dx<6 && dy>=6 && dy<37) ||
   (seg[0] && dx>=6 && dx<38 && dy>=37 && dy<43));
 end
endfunction
wire [3:0] left_digit=scene==2?0:scene==3?11:(floor_no>=10?1:0);
wire [3:0] right_digit=scene==2?10:scene==3?11:units;

wire digit_right=x>=84;
wire [5:0] digit_dx=x[5:0]-(digit_right?6'd20:6'd24);
wire [9:0] digit_dy={1'b0,y}-digit_y;
wire digit_hit=in_de && (scene!=2 || scene_blink) &&
 (((x>=24 && x<68)||(x>=84 && x<128)) && y>=digit_y && digit_dy<80) &&
 seven_pixel(digit_right?right_digit:left_digit,digit_dx,digit_dy[6:0]);
wire [10:0] ay=y-arrow_y;
wire [10:0] ax=x>=75 ? x-75 : 75-x;
wire arrow_hit=in_de && x<150 && (scene==0 || (scene==1 && floor_no>1)) && y>=arrow_y && ay<34 &&
 ((going_up && scene==0) ? ((ay<16 && ax<=ay) || (ay>=12 && ax<=4)) :
             ((ay>=18 && ax<=33-ay) || (ay<22 && ax<=4)));
reg text_hit;
reg [7:0] selected_char;
reg [3:0] text_row;
reg [2:0] text_col;
reg [111:0] message;reg [3:0] message_id;
reg signed [10:0] lx;reg [8:0] ly;reg [3:0] length;

wire [7:0] shared_line;
generate if(EXTERNAL_FONT_ENABLE && SCENE_ENABLE)begin: shared_text_layout
 scene_line_rom u_lines(.clk(clk),.address({scene,y[8:1]}),.code(shared_line));
 assign scene_line_code=shared_line[3:0];
 always @*begin
  text_hit=0;selected_char=32;text_row=0;text_col=0;
  message=0;message_id=0;lx=0;ly=0;length=0;
  case(shared_line[7:4])
   1:begin message_id=0;lx=x-23;length=13;ly=y-28;end
   2:begin message_id=1;lx=x-35;length=10;ly=y-28;end
   3:begin message_id=2;lx=x-35;length=10;ly=y-28;end
   4:begin message_id=going_up?3:4;lx=x-35;length=10;ly=y-260;end
   5:begin message_id=5;lx=x-43;length=8;ly=y-260;end
   6:begin message_id=6;lx=x-35;length=10;ly=y-260;end
   7:begin message_id=7;lx=x-35;length=10;ly=y-260;end
   8:begin message_id=8;lx=x-31;length=11;ly=y-322;end
   9:begin message_id=floor_no==1?9:10;lx=floor_no==1?x-35:x-43;length=floor_no==1?10:8;ly=y-322;end
   10:begin message_id=11;lx=x-39;length=9;ly=y-322;end
   11:begin message_id=12;lx=x-31;length=11;ly=y-322;end
   default:begin end
  endcase
  if(in_de && x<150 && length!=0 && lx>=0 && lx<length*8)begin
   text_hit=1;text_row=ly[3:0];text_col=lx[2:0];
  end
 end
end else begin: legacy_text_layout
 assign shared_line=0;assign scene_line_code=0;
always @* begin
 text_hit=0;selected_char=32;text_row=0;text_col=0;
 message=0;message_id=0;lx=0;ly=0;length=0;
 if(y>=28 && y<44)begin
  if(scene==1)begin message="FIRE ALARM";message_id=4'd1;lx=x-35;length=10;end
  else if(scene==3)begin message="INSPECTION";message_id=4'd2;lx=x-35;length=10;end
  else begin message="ELEVATOR INFO";lx=x-23;length=13;end
  ly=y-28;
 end else if(y>=260 && y<276)begin
  if(scene==1)begin message="EVACUATE";message_id=4'd5;lx=x-43;length=8;end
  else if(scene==2)begin message="OVERLOADED";message_id=4'd6;lx=x-35;length=10;end
  else if(scene==3)begin message="OUT OF SVC";message_id=4'd7;lx=x-35;length=10;end
  else begin message=going_up?"GOING UP  ":"GOING DOWN";message_id=going_up?4'd3:4'd4;lx=x-35;length=10;end
  ly=y-260;
 end else if(y>=322 && y<338)begin
  if(scene==1)begin
   if(floor_no==1)begin message="EXIT AT 1F";message_id=4'd9;lx=x-35;length=10;end
   else begin message="NON-STOP";message_id=4'd10;lx=x-43;length=8;end
  end else if(scene==2)begin message="DOOR OPEN";message_id=4'd11;lx=x-39;length=9;end
  else if(scene==3)begin message="MANUAL MODE";message_id=4'd12;lx=x-31;length=11;end
  else begin message="DOOR CLOSED";message_id=4'd8;lx=x-31;length=11;end
  ly=y-322;
 end
 if(in_de && x<150 && length!=0 && lx>=0 && lx<length*8)begin
  text_hit=1;selected_char=message[(length-1-lx[6:3])*8+:8];text_row=ly;text_col=lx%8;
 end
end
end endgenerate
always @(posedge clk or posedge rst)begin
 if(rst)begin
  x<=0;y<=0;de_prev<=0;vs_prev<=0;floor_no<=1;going_up<=1;animation_step<=0;frame_count<=0;scene_previous<=0;
 end else begin
  de_prev<=in_de;vs_prev<=in_vs;
  if(frame_tick)begin
   x<=0;y<=0;
   scene_previous<=scene;
   if(scene!=scene_previous)begin
    frame_count<=0;animation_step<=0;
    if(scene==1)going_up<=0;
    else if(scene==0 && floor_no==1)going_up<=1;
   end else if(scene==1)begin
    if(frame_count==FIRE_FLOOR_FRAMES-1)begin
     frame_count<=0;
     if(floor_no>1)begin floor_no<=floor_no-1'b1;animation_step<=0;end
    end else begin frame_count<=frame_count+1'b1;if(animation_step<15)animation_step<=animation_step+1'b1;end
   end else if(scene==0)begin
    if(frame_count==FLOOR_FRAMES-1)begin
     frame_count<=0;animation_step<=0;
     if(going_up)begin floor_no<=floor_no+1'b1;if(floor_no==11)going_up<=0;end
     else begin floor_no<=floor_no-1'b1;if(floor_no==2)going_up<=1;end
    end else begin frame_count<=frame_count+1'b1;if(animation_step<15)animation_step<=animation_step+1'b1;end
   end else begin frame_count<=0;animation_step<=15;end
  end else begin
   if(in_de)x<=x+1'b1;else x<=0;
   if(de_prev && !in_de && y<360)y<=y+1'b1;
  end
 end
end
reg [23:0] rgb0,rgb1;
reg d0,h0,v0,d1,h1,v1,th0,th1,number0,number1,arrow0,arrow1;
reg [7:0] char0,font1;
reg [3:0] row0;
reg [2:0] col0,col1;
wire [7:0] font;
generate if(!EXTERNAL_FONT_ENABLE)begin: local_font
 subtitle_font8x16 u_font(.ascii(char0),.row(row0),.pixels(font));
end else begin assign font=0;end endgenerate
assign text_request={text_hit && !eco,(10'd448+{2'b0,message_id,lx[6:3]})};
assign font_request={th0 && !eco,(EXTERNAL_FONT_ENABLE?external_text:char0),row0};
reg green0,green1;
function [7:0] darken;input [7:0] v;begin darken=v-(v>>2);end endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin
  rgb0<=0;rgb1<=0;out_rgb<=0;d0<=0;h0<=0;v0<=0;d1<=0;h1<=0;v1<=0;out_de<=0;out_hs<=0;out_vs<=0;
  th0<=0;th1<=0;number0<=0;number1<=0;arrow0<=0;arrow1<=0;char0<=32;font1<=0;row0<=0;col0<=0;col1<=0;green0<=0;green1<=0;
 end else begin

  if(eco)rgb0<=24'h020408;
  else if(x>=150 && x<640 && y<360)begin
   case(scene)
    1:rgb0<=24'h5a0e17;
    2:rgb0<={darken(in_rgb[23:16]),darken(in_rgb[15:8]),darken(in_rgb[7:0])};
    3:rgb0<=24'h141c2b;
    default:rgb0<=in_rgb;
   endcase
  end
  else rgb0<=scene==1?24'h5a0e17:scene==3?24'h141c2b:MEDIA_BG;
  d0<=in_de;h0<=in_hs;v0<=in_vs;th0<=text_hit && !eco;number0<=digit_hit;arrow0<=arrow_hit;
  char0<=selected_char;row0<=text_row;col0<=text_col;green0<=scene==2 && y>=322;green1<=green0;
  rgb1<=rgb0;d1<=d0;h1<=h0;v1<=v0;th1<=th0;number1<=number0;arrow1<=arrow0;font1<=font;col1<=col0;
  out_de<=d1;out_hs<=h1;out_vs<=v1;
  if(!NATIVE_TEXT && number1)out_rgb<=eco?24'h4c5968:scene==2?24'hffb800:(scene==1 && floor_no==1 && !scene_blink)?24'hd04a37:24'hffffff;
  else if(arrow1)out_rgb<=eco?24'h285566:scene==1?24'hff4545:24'h64daff;
  else if(!NATIVE_TEXT && th1 && (EXTERNAL_FONT_ENABLE?external_font_row[7-col1]:font1[7-col1]))out_rgb<=green1?24'h47df8c:scene==1?24'hffd34d:scene==2?24'hffb800:scene==3?24'hd4e2ec:24'hb8cce5;
  else out_rgb<=rgb1;
 end
end
endmodule
