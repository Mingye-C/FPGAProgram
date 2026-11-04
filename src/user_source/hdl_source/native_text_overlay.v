module native_text_overlay(input clk,rst,input [124:0] state,input [16:0] sensor_state,
 input [10:0] x,input [9:0] y,input [23:0] in_rgb,input in_de,in_sof,in_eol,
 output reg [23:0] out_rgb,output reg out_de,out_sof,out_eol);
wire [1:0] scene;wire blink,eco;wire [1:0] eco_state;wire [5:0] depth;wire presence;
wire [3:0] floor_no;wire up;wire [4:0] slide;wire [10:0] phase;wire chinese,sub_enable;
wire [7:0] brightness;wire [3:0] contrast;wire osd_on,reset_notice;wire [63:0] info;wire [7:0] numbers;wire info_valid,video;
wire auto_play;
assign {auto_play,scene,blink,eco,eco_state,depth,presence,floor_no,up,slide,phase,chinese,sub_enable,brightness,contrast,osd_on,reset_notice,info,numbers,info_valid,video}=state;
reg[6:0]notice_frames;reg[1:0]notice_kind;reg prev_video,prev_auto,notice_armed;
always @(posedge clk or posedge rst)begin
 if(rst)begin notice_frames<=0;notice_armed<=0;notice_kind<=0;prev_video<=0;prev_auto<=1;end
 else if(x==1 && y==748)begin
  prev_video<=video;prev_auto<=auto_play;
  if(!notice_armed)begin notice_armed<=floor_no!=0;notice_frames<=0;end
  else if(video!=prev_video)begin notice_frames<=120;notice_kind<=video?1:0;end
  else if(auto_play!=prev_auto)begin notice_frames<=120;notice_kind<=auto_play?2:3;end
  else if(notice_frames!=0)notice_frames<=notice_frames-1'b1;
 end
end
reg [5:0] command_address;wire [48:0] command;reg scan_valid,scan_end;reg [9:0] target_y;
wire logo_valid;wire[23:0]logo_rgb;
sidebar_logo_rom u_sidebar_logo(.clk(clk),.rst(rst),.enable((scene==0 && !eco && eco_state==0)||scene==2),.in_de(in_de),.x(x),.y(y),.valid(logo_valid),.rgb(logo_rgb));
reg [12:0] ticker_offset;
reg [1:0] span_count;reg [40:0] span0,span1;
native_command_rom u_commands(.clk(clk),.address(command_address),.q(command));
wire [2:0] condition=command[48:46];wire [9:0] top_y=command[45:36];
wire [10:0] left_x=command[35:25];wire [5:0] count=command[24:19];
wire [10:0] label_base=command[18:8];wire is_cn=command[7];wire [2:0] palette=command[6:4];wire [3:0] flags=command[3:0];
wire scene_match=condition==0 || (condition==1 && scene==0 && !eco) || (condition==2 && scene==1) ||
 (condition==3 && scene==2) || (condition==4 && scene==3) || (condition==5 && scene==0 && eco);
wire visible=flags==15?notice_frames!=0 && !eco:flags>=1 && flags<=3 ? info_valid && !video :
 (flags==4 || flags==5)?osd_on && !reset_notice:flags==6?osd_on && reset_notice:
 flags==7?sub_enable && !eco:flags==10?presence && !eco: !eco || condition==5;
wire [4:0] row_in_line=target_y-top_y;
wire command_hit=scene_match && visible && count!=0 && target_y>=top_y && target_y<top_y+((flags==12||flags==13)?10'd24:10'd32);
wire [10:0] actual_left=(flags==8 && up || flags==9 && floor_no!=1)?11'd86:left_x;
wire [40:0] packed_span={actual_left,count,label_base,is_cn,palette,flags,row_in_line};
always @(posedge clk or posedge rst)begin
 if(rst)begin ticker_offset<=0;command_address<=0;scan_valid<=0;scan_end<=0;target_y<=0;span_count<=0;span0<=0;span1<=0;end
 else begin
  if(x==1280)begin
   ticker_offset<={1'b0,phase,1'b0}-13'd1260;
   target_y<=y==749?10'd0:y+1'b1;command_address<=0;scan_valid<=0;scan_end<=0;
   span_count<=0;span0<=0;span1<=0;
  end else if(x>=1281 && x<1346)begin
   scan_valid<=1;
   if(command_address==63)scan_end<=1;else command_address<=command_address+1'b1;
   if(scan_valid && !scan_end && command_hit)begin
    case(span_count)0:span0<=packed_span;1:span1<=packed_span;endcase
    if(span_count!=2)span_count<=span_count+1'b1;
`ifndef SYNTHESIS
    if(span_count==2)$fatal(1,"Native text scanline exceeds two spans y=%0d",target_y);
`endif
   end
  end
 end
end
wire [40:0] spans[0:1];assign spans[0]=span0;assign spans[1]=span1;
reg [40:0] selected_next;reg hit_next;reg[10:0]next_lx,pre_lx;
reg pre_back_allowed;
reg [40:0] selected;reg hit;reg [10:0] pre_x;reg [9:0] pre_y;reg [23:0] pre_rgb;reg pre_de,pre_sof,pre_eol;integer k;reg [11:0] delta,width;reg candidate;
always @*begin
 selected_next=0;hit_next=0;next_lx=0;delta=0;width=0;candidate=0;
 for(k=0;k<2;k=k+1)begin
  delta={1'b0,x}-{1'b0,spans[k][40:30]};
  width=(spans[k][8:5]==12||spans[k][8:5]==13)?12'd160:spans[k][8:5]==7?12'd940:(spans[k][12]?{1'b0,spans[k][29:24],5'b0}:{2'b0,spans[k][29:24],4'b0});
  candidate=k<span_count && in_de && x>=spans[k][40:30] && delta<width;
  if(candidate)begin selected_next=spans[k];hit_next=1;next_lx=delta[10:0];end
 end
end
wire [10:0] lx=pre_lx;

wire selected_cn=selected[12];wire [3:0] selected_flags=selected[8:5];wire [2:0] selected_palette=selected[11:9];
wire sensor_line=selected_flags[3:1]==3'd6;

wire [5:0] char_index=selected_cn?(lx>>5):(lx>>4);
wire[7:0]sensor_dx=lx[7:0]-8'd72;
wire[3:0]sensor_char=lx<24?0:lx<48?1:lx<72?2:4'd3+{1'b0,sensor_dx[6:4]};

reg[12:0]next_ticker_pos,next_ticker_t;reg[10:0]next_ticker_base;
reg next_ticker_cn,next_ticker_valid;reg[6:0]next_ticker_len;reg[8:0]next_ticker_dynamic;
reg[12:0]saved_ticker_t;reg[10:0]saved_ticker_base;reg saved_ticker_cn,saved_ticker_valid;reg[8:0]saved_ticker_dynamic;
always @*begin
 next_ticker_valid=1;next_ticker_dynamic=0;next_ticker_len=41;
  next_ticker_pos={2'd0,x}+ticker_offset;next_ticker_t=next_ticker_pos;next_ticker_cn=0;next_ticker_base=1536;
  case(scene)1:next_ticker_len=36;2:next_ticker_len=16;3:next_ticker_len=14;default:next_ticker_len=41;endcase
  if(scene==0)begin

   next_ticker_pos={2'd0,(next_ticker_pos[10:8]-(next_ticker_pos[12]?3'd1:3'd0)),next_ticker_pos[7:0]};next_ticker_t=next_ticker_pos;
   if(next_ticker_pos>=960 && next_ticker_pos<1472)begin next_ticker_cn=1;next_ticker_base=1600;next_ticker_t=next_ticker_pos-960;end
  end
  else if(next_ticker_pos<({6'd0,next_ticker_len}<<4))begin case(scene)1:next_ticker_base=1664;2:next_ticker_base=1792;default:next_ticker_base=1920;endcase end
  else if(next_ticker_pos<({6'd0,next_ticker_len}<<4)+48)begin next_ticker_t=next_ticker_pos-({6'd0,next_ticker_len}<<4);next_ticker_base=0;next_ticker_dynamic={1'b1,next_ticker_t[5:4]==1?8'd47:8'd32};end
  else begin
   next_ticker_t=next_ticker_pos-({6'd0,next_ticker_len}<<4)-48;next_ticker_cn=1;case(scene)1:next_ticker_base=1728;2:next_ticker_base=1856;default:next_ticker_base=1984;endcase
  end
  if(scene==0)next_ticker_valid=next_ticker_pos<656 || (next_ticker_pos>=960 && next_ticker_pos<1472);
  else case(scene)1:next_ticker_valid=next_ticker_pos<1136;2:next_ticker_valid=next_ticker_pos<752;3:next_ticker_valid=next_ticker_pos<880;endcase
end
always @(posedge clk or posedge rst)begin
 if(rst)begin saved_ticker_t<=0;saved_ticker_base<=0;saved_ticker_cn<=0;saved_ticker_valid<=0;saved_ticker_dynamic<=0;end
 else begin saved_ticker_t<=next_ticker_t;saved_ticker_base<=next_ticker_base;saved_ticker_cn<=next_ticker_cn;saved_ticker_valid<=next_ticker_valid;saved_ticker_dynamic<=next_ticker_dynamic;end
end
reg [10:0] text_address;reg [4:0] col,row;reg [8:0] dynamic;reg ticker_valid;
reg [12:0] pos,t;reg [10:0] base;reg cn;
reg [6:0] en_len;reg [15:0] digit_string;reg [15:0] bcd;reg [1:0] digit_index;
reg [3:0] bcd_digit;reg [7:0] code_override;
always @*begin
 text_address=selected[23:13]|{5'd0,char_index};col=selected_cn?lx[4:0]:{1'b0,lx[3:0]};row=selected[4:0];
 dynamic=0;ticker_valid=1;pos=0;t=0;base=0;cn=selected_cn;en_len=41;digit_string=" 0";bcd=0;digit_index=0;bcd_digit=0;code_override=32;
 if(sensor_line)begin
  text_address=selected[23:13]|{7'd0,sensor_char};
  col=lx<24?lx[4:0]:lx<48?lx-24:lx<72?lx-48:{1'b0,sensor_dx[3:0]};
  row=lx<72?selected[4:0]:selected[4:0]+(selected[4:0]>>2);
  if(lx>=72 && lx<104)begin
   bcd_digit=selected_flags[0]?(lx<88?sensor_state[7:4]:sensor_state[3:0]):(lx<88?sensor_state[15:12]:sensor_state[11:8]);
   dynamic={1'b1,sensor_state[16]?{4'h3,bcd_digit}:8'd45};
  end
 end
 if(selected_flags==15)text_address=11'd1504|{7'd0,notice_kind,2'b0}|{5'd0,char_index};
 if(selected_flags==14)text_address=(up?11'd1488:11'd1492)|{5'd0,char_index};
 if(selected_flags==8)text_address=(up?11'd496:11'd512)|{5'd0,char_index};
 if(selected_flags==9)text_address=(floor_no==1?11'd592:11'd608)|{5'd0,char_index};
 if(selected_flags==1)begin
  if(char_index==5)dynamic={1'b1,8'd48+{4'd0,numbers[3:0]}};
  if(char_index==8)dynamic={1'b1,8'd48+{4'd0,numbers[7:4]}};
 end
 if(selected_flags==2 || selected_flags==3)begin
  bcd=selected_flags==2?(char_index<8?info[15:0]:info[31:16]):(char_index<8?info[47:32]:info[63:48]);
  if(char_index>=4 && char_index<=7 || char_index>=9 && char_index<=12)begin
   digit_index=char_index<8?char_index-4:char_index-9;bcd_digit=bcd[(3-digit_index)*4+:4];
   code_override=48+{4'd0,bcd_digit};
   if(digit_index==0 && bcd[15:12]==0 || digit_index==1 && bcd[15:8]==0 || digit_index==2 && bcd[15:4]==0)code_override=32;
   dynamic={1'b1,code_override};
  end
 end
 if(selected_flags==4)begin
  case(brightness[7:4])1,15:digit_string="16";2,14:digit_string="32";3,13:digit_string="48";4,12:digit_string="64";5,11:digit_string="80";endcase
  case(char_index)11:dynamic={1'b1,brightness==0?8'd32:brightness[7]?8'd45:8'd43};12:dynamic={1'b1,digit_string[15:8]};13:dynamic={1'b1,digit_string[7:0]};endcase
 end
 if(selected_flags==5)case(char_index)
 9:dynamic={1'b1,contrast<5?8'd48:8'd49};11:dynamic={1'b1,contrast<5?8'd53+{4'd0,contrast}:8'd43+{4'd0,contrast}};
 endcase
 if(selected_flags==7)begin
  text_address=saved_ticker_base|(saved_ticker_cn?{3'd0,saved_ticker_t[12:5]}:{2'd0,saved_ticker_t[12:4]});
  col=saved_ticker_cn?saved_ticker_t[4:0]:{1'b0,saved_ticker_t[3:0]};
  dynamic=saved_ticker_dynamic;ticker_valid=saved_ticker_valid;
 end
end
wire [7:0] label_code;
native_label_rom u_labels(.clk(clk),.address(text_address),.q(label_code));
reg hit0,hit1;reg [8:0] dyn0;reg [4:0] col0,row0;reg [2:0] color0,color1;
wire [7:0] glyph_code=dyn0[8]?dyn0[7:0]:label_code;
wire [1:0] coverage,shadow;
native_font_rom u_font(.clk(clk),.code(glyph_code),.row(row0),.col(col0),.ink(coverage),.shadow(shadow));

function [1:0] seven;
 input [3:0] n;input [6:0] dx;input [7:0] dy;reg [6:0] s;reg ink;
 begin
  case(n)0:s=7'b1111110;1:s=7'b0110000;2:s=7'b1101101;3:s=7'b1111001;4:s=7'b0110011;5:s=7'b1011011;
  6:s=7'b1011111;7:s=7'b1110000;8:s=7'b1111111;9:s=7'b1111011;10:s=7'b0001110;default:s=7'b0000001;endcase
  ink=(s[6]&&dx>=10&&dx<86&&dy<9)||(s[5]&&dx>=87&&dy>=10&&dy<67)||(s[4]&&dx>=87&&dy>=77&&dy<134)||
  (s[3]&&dx>=10&&dx<86&&dy>=135)||(s[2]&&dx<9&&dy>=77&&dy<134)||(s[1]&&dx<9&&dy>=10&&dy<67)||
  (s[0]&&dx>=10&&dx<86&&dy>=68&&dy<77);
  seven=ink?((dx==0||dx==95||dy==0||dy==143)?2'd2:2'd3):2'd0;
 end
endfunction
wire right_digit=pre_x>=156;wire [6:0] digit_x=pre_x-(right_digit?11'd156:11'd42);
wire [3:0] units=floor_no>=10?floor_no-4'd10:floor_no;
wire [3:0] digit=right_digit?(scene==2?4'd10:scene==3?4'd11:units):(scene==2?4'd0:scene==3?4'd11:floor_no>=10?4'd1:4'd0);
wire [9:0] digit_top=scene==2 || scene==3?10'd220:up?10'd220+{4'd0,slide,1'b0}:10'd220-{4'd0,slide,1'b0};
wire [9:0] digit_y=pre_y-digit_top;
wire digit_area=pre_de && ((pre_x>=42&&pre_x<138)||(pre_x>=156&&pre_x<252))&&pre_y>=digit_top&&digit_y<144 && (scene!=2 || blink);
wire [1:0] dc=digit_area?seven(digit,digit_x,digit_y[7:0]):2'd0;
reg title0,title1,title2;wire [1:0] title_ink,title_shadow;
native_eco_title_rom u_eco_title(.clk(clk),.x(x0),.y(y0),.ink(title_ink),.shadow(title_shadow));
reg [1:0] digit0,digit1,digit2;reg hit2,allowed2;reg [23:0] rgb0,rgb1,rgb2,rgb3,rgb4;reg d0,d1,d2,d3,d4,f0,f1,f2,f3,f4,l0,l1,l2,l3,l4;
reg [10:0] x0;reg [9:0] y0;
reg [23:0] foreground0;reg [4:0] gain0;reg allowed0,allowed1;
(* use_dsp="yes" *)reg [12:0] fr1,fg1,fb1;
reg [23:0] foreground2,foreground3;reg [1:0] alpha3;reg shadow3;
wire [23:0] foreground1={fr1[11:4],fg1[11:4],fb1[11:4]};
reg [23:0] pixel;
always @*begin
 case(color0)1:foreground0=24'hbdd9ec;2:foreground0=24'h64daff;3:foreground0=24'hffd34d;4:foreground0=24'h47df8c;default:foreground0=24'hffffff;endcase
 if(title0)foreground0=24'h637180;
 if(digit0!=0)foreground0=eco?24'h4c5968:scene==2?24'hffb800:(scene==1&&floor_no==1&&!blink)?24'hd04a37:24'hffffff;
 gain0=16;allowed0=1;
 if(scene==0 && (eco_state==1 || eco_state==3))begin
  if(x0<300)gain0=depth>=24?5'd4:5'd16-{1'b0,depth[5:1]};
  else if(depth>=32 || (y0>=360?y0-360:360-y0)>=((32-depth)*12))allowed0=0;
 end
end
function [7:0] mix;input [7:0] bg,fg;input [1:0] alpha;reg [9:0] q;
 begin case(alpha)1:q={2'd0,bg}+{1'b0,bg,1'b0}+{2'd0,fg}+2;2:q={2'd0,bg}+{2'd0,fg}+{1'b0,fg,1'b0}+2;default:q={fg,2'b0};endcase mix=q[9:2];end
endfunction

always @*begin
 pixel=rgb3;
 if(alpha3!=0)pixel={mix(rgb3[23:16],foreground3[23:16],alpha3),mix(rgb3[15:8],foreground3[15:8],alpha3),mix(rgb3[7:0],foreground3[7:0],alpha3)};
 else if(shadow3)pixel={1'b0,rgb3[23:17],1'b0,rgb3[15:9],1'b0,rgb3[7:1]};
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  selected<=0;hit<=0;pre_lx<=0;pre_x<=0;pre_y<=0;pre_rgb<=0;pre_de<=0;pre_sof<=0;pre_eol<=0;pre_back_allowed<=0;
  title0<=0;title1<=0;title2<=0;hit2<=0;allowed2<=0;digit2<=0;
  hit0<=0;hit1<=0;dyn0<=0;col0<=0;row0<=0;color0<=0;color1<=0;digit0<=0;digit1<=0;
  rgb0<=0;rgb1<=0;rgb2<=0;rgb3<=0;rgb4<=0;out_rgb<=0;d0<=0;d1<=0;d2<=0;d3<=0;d4<=0;out_de<=0;f0<=0;f1<=0;f2<=0;f3<=0;f4<=0;out_sof<=0;l0<=0;l1<=0;l2<=0;l3<=0;l4<=0;out_eol<=0;x0<=0;y0<=0;
  fr1<=0;fg1<=0;fb1<=0;foreground2<=0;foreground3<=0;alpha3<=0;shadow3<=0;allowed1<=0;
 end else begin
  selected<=selected_next;hit<=hit_next;pre_lx<=next_lx;pre_x<=x;pre_y<=y;

  pre_back_allowed<=scene==0 && !eco && x>=300 && !logo_valid;
  pre_rgb<=logo_valid?logo_rgb:in_rgb;pre_de<=in_de;pre_sof<=in_sof;pre_eol<=in_eol;
  title0<=scene==0&&eco&&pre_de&&pre_x>=22&&pre_x<278&&pre_y>=548&&pre_y<612;title1<=title0;title2<=title1;
  hit0<=hit && ticker_valid;dyn0<=dynamic;col0<=col;row0<=row;color0<=selected_palette;digit0<=dc;rgb0<=pre_back_allowed && hit && selected_flags!=7?{1'b0,pre_rgb[23:17],1'b0,pre_rgb[15:9],1'b0,pre_rgb[7:1]}:pre_rgb;d0<=pre_de;f0<=pre_sof;l0<=pre_eol;x0<=pre_x;y0<=pre_y;
  hit1<=hit0;color1<=color0;digit1<=digit0;rgb1<=rgb0;d1<=d0;f1<=f0;l1<=l0;
  fr1<=foreground0[23:16]*gain0;fg1<=foreground0[15:8]*gain0;fb1<=foreground0[7:0]*gain0;allowed1<=allowed0;
  hit2<=hit1;allowed2<=allowed1;digit2<=digit1;foreground2<=foreground1;
  alpha3<=allowed2?(title2?title_ink:digit2!=0?digit2:hit2?coverage:2'd0):2'd0;
  shadow3<=allowed2 && (title2?title_shadow!=0:hit2 && shadow!=0);foreground3<=foreground2;
  rgb2<=rgb1;d2<=d1;f2<=f1;l2<=l1;
  rgb3<=rgb2;d3<=d2;f3<=f2;l3<=l2;
  rgb4<=pixel;d4<=d3;f4<=f3;l4<=l3;
  out_rgb<=rgb4;out_de<=d4;out_sof<=f4;out_eol<=l4;
 end
end
endmodule
