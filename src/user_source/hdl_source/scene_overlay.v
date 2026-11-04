module scene_overlay #(parameter NATIVE_TEXT=0,EXTERNAL_TEXT_ENABLE=0,PARALLEL=0,ECO_ENABLE=0,ECO_TEXT_X=58,ECO_TEXT_Y=390,ECO_TITLE_ENABLE=0)(input clk,input rst,input [1:0] scene_mode,input blink,input eco_active,input presence_display,
 input [23:0] in_rgb,input in_de,in_hs,in_vs,
 input [3:0] line_descriptor,input [9:0] raster_x,input [8:0] raster_y,input [23:0] background_p1,output reg out_mask,
 output [12:0] font_request,output [14:0] chinese_request,
 output [10:0] text_request,input [7:0] external_text,
 input [7:0] ascii_row,input chinese_pixel,
 output reg [23:0] out_rgb,output reg out_de,out_hs,out_vs);
reg [9:0] own_x;reg [8:0] own_y;wire [9:0] x=PARALLEL?raster_x:own_x;wire [8:0] y=PARALLEL?raster_y:own_y;reg pd,pv;wire tick=pv && !in_vs;
wire eco=ECO_ENABLE && scene_mode==0 && eco_active;
wire presence_hit=ECO_ENABLE && scene_mode==0 && presence_display && !eco;
reg [2:0] line_id;reg [9:0] left_x;reg [8:0] top_y,text_width;
reg chinese,scale2,accent;
wire [3:0] line_code;
generate if(PARALLEL)begin assign line_code=line_descriptor;end
else begin wire [7:0] lc;scene_line_rom u_lines(.clk(clk),.address({scene_mode,y[8:1]}),.code(lc));assign line_code=lc[3:0];end endgenerate
always @*begin
 line_id=0;left_x=0;top_y=0;text_width=0;chinese=0;scale2=0;accent=0;
 case(line_code)
 4'd1:begin line_id=3'd0;left_x=10'd283;top_y=9'd90;chinese=0;scale2=1;accent=1;text_width=9'd224;end
 4'd2:begin line_id=3'd1;left_x=10'd299;top_y=9'd130;chinese=1;scale2=1;accent=0;text_width=9'd192;end
 4'd3:begin line_id=3'd2;left_x=10'd299;top_y=9'd172;chinese=1;scale2=1;accent=1;text_width=9'd192;end
 4'd4:begin line_id=3'd0;left_x=10'd331;top_y=9'd104;chinese=0;scale2=0;accent=1;text_width=9'd128;end
 4'd5:begin line_id=3'd1;left_x=10'd315;top_y=9'd142;chinese=1;scale2=0;accent=0;text_width=9'd160;end
 4'd6:begin line_id=3'd2;left_x=10'd311;top_y=9'd180;chinese=0;scale2=0;accent=0;text_width=9'd168;end
 4'd7:begin line_id=3'd0;left_x=10'd275;top_y=9'd32;chinese=0;scale2=1;accent=0;text_width=9'd240;end
 4'd8:begin line_id=3'd1;left_x=10'd315;top_y=9'd80;chinese=1;scale2=1;accent=0;text_width=9'd160;end
 4'd9:begin line_id=3'd2;left_x=10'd243;top_y=9'd128;chinese=0;scale2=0;accent=0;text_width=9'd128;end
 4'd10:begin line_id=3'd3;left_x=10'd243;top_y=9'd150;chinese=0;scale2=0;accent=0;text_width=9'd144;end
 4'd11:begin line_id=3'd4;left_x=10'd243;top_y=9'd172;chinese=0;scale2=0;accent=0;text_width=9'd72;end
 4'd12:begin line_id=3'd5;left_x=10'd243;top_y=9'd194;chinese=0;scale2=0;accent=0;text_width=9'd80;end
 4'd13:begin line_id=3'd6;left_x=10'd323;top_y=9'd226;chinese=1;scale2=0;accent=0;text_width=9'd144;end
 4'd14:begin line_id=3'd7;left_x=10'd537;top_y=9'd210;chinese=0;scale2=0;accent=1;text_width=9'd32;end
 default:begin end
 endcase
 if(scene_mode==0)begin
  if(ECO_TITLE_ENABLE && eco && y>=282 && y<314)begin left_x=11;top_y=282;text_width=128;chinese=1;scale2=1;end
  else if(ECO_TITLE_ENABLE && eco && y>=326 && y<342)begin left_x=23;top_y=326;text_width=104;end
  else if(!ECO_TITLE_ENABLE && eco && y>=ECO_TEXT_Y && y<ECO_TEXT_Y+16)begin left_x=ECO_TEXT_X;top_y=ECO_TEXT_Y;text_width=64;chinese=1;end
  else if(presence_hit && y>=70 && y<86)begin left_x=59;top_y=70;text_width=32;chinese=1;end
 end
end
wire [9:0] lx=x-left_x;wire [4:0] ly=y[4:0]-top_y[4:0];
wire th=in_de && text_width!=0 && x>=left_x && lx<text_width;
wire [4:0] char_index=chinese?(scale2?(lx>>5):(lx>>4)):(scale2?(lx>>4):(lx>>3));
wire [3:0] glyph_col=scale2?(lx>>1):lx;
wire [3:0] glyph_row=scale2?(ly>>1):ly;
wire card=scene_mode==2 && x>=175 && x<615 && y>=100 && y<240;
wire fire_border=scene_mode==1 && x>=150 && x<640 && y<360 && (x<153 || x>=637 || y<3 || y>=357);
wire overload_border=card && (x<177 || x>=613 || y<102 || y>=238);
wire inspect_border=scene_mode==3 && (x>=155 && x<635 && y>=70 && y<320 && (x<157 || x>=633 || y<72 || y>=318));
wire [9:0] triangle_dx=x>=395?x-395:395-x;
wire [8:0] triangle_dy=y-9'd90;
wire triangle=scene_mode==1 && y>=90 && y<154 && triangle_dx<={2'b0,triangle_dy[8:1]};
wire exclamation=triangle && ((x>=392 && x<=398 && y>=114 && y<139)||(x>=392 && x<=398 && y>=146 && y<152));
reg [2:0] geom;reg card0,card1;
always @*begin
 geom=0;
 if(fire_border)geom=1;
 else if(overload_border)geom=2;
 else if(inspect_border)geom=3;
 else if(exclamation)geom=5;
 else if(triangle)geom=4;
end
wire [9:0] tile_addr0=scene_mode==0?((eco?(ECO_TITLE_ENABLE && !chinese?10'd656:10'd1012):10'd1010)+char_index):(scene_mode==1?10'd0:scene_mode==2?10'd96:10'd192)+{2'd0,line_id,char_index};wire [7:0] code1;
generate if(EXTERNAL_TEXT_ENABLE)begin assign code1=external_text;end
else begin scene_text_rom u_text(.clk(clk),.address(tile_addr0),.address_b(10'd0),.code(code1),.code_b());end endgenerate
assign text_request={th,tile_addr0};
reg [23:0] rgb0,rgb1,rgb2;
reg d0,h0,v0,d1,h1,v1,d2,h2,v2,hit0,hit1,hit2,accent0,accent1,accent2,cn2;
reg [3:0] row0,row1,col0,col1,col2;
reg [2:0] g0,g1,g2;
reg [1:0] mode0,mode1,mode2;reg b0,b1,b2;
assign font_request={hit0 && !code1[7],code1,row0};
assign chinese_request={hit0 && code1[7],code1[5:0],row0,col0};
wire text_ink=cn2?chinese_pixel:ascii_row[7-col1[2:0]];
function [7:0] card_mix;input [7:0] c;input [7:0] bias;begin card_mix=(c>>1)+bias;end endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin own_x<=0;own_y<=0;pd<=0;pv<=0;end
 else begin
  pd<=in_de;pv<=in_vs;
  if(tick)begin own_x<=0;own_y<=0;end
  else begin if(in_de)own_x<=x+1'b1;else own_x<=0;if(pd && !in_de && y<360)own_y<=y+1'b1;end
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  rgb0<=0;rgb1<=0;rgb2<=0;out_rgb<=0;out_mask<=0;card0<=0;card1<=0;d0<=0;h0<=0;v0<=0;d1<=0;h1<=0;v1<=0;d2<=0;h2<=0;v2<=0;out_de<=0;out_hs<=0;out_vs<=0;
  hit0<=0;hit1<=0;hit2<=0;accent0<=0;accent1<=0;accent2<=0;cn2<=0;row0<=0;row1<=0;col0<=0;col1<=0;col2<=0;g0<=0;g1<=0;g2<=0;mode0<=0;mode1<=0;mode2<=0;b0<=0;b1<=0;b2<=0;
 end else begin
  card0<=card;card1<=card0;
  rgb0<=PARALLEL?24'd0:card?{card_mix(in_rgb[23:16],8'd8),card_mix(in_rgb[15:8],8'd9),card_mix(in_rgb[7:0],8'd11)}:in_rgb;
  d0<=in_de;h0<=in_hs;v0<=in_vs;hit0<=th;accent0<=accent;row0<=glyph_row;col0<=glyph_col;
  g0<=in_de?geom:3'd0;mode0<=scene_mode;b0<=blink;
  rgb1<=rgb0;d1<=d0;h1<=h0;v1<=v0;hit1<=hit0;accent1<=accent0;row1<=row0;col1<=col0;g1<=g0;mode1<=mode0;b1<=b0;
  rgb2<=rgb1;d2<=d1;h2<=h1;v2<=v1;hit2<=hit1;accent2<=accent1;cn2<=code1[7];col2<=col1;g2<=g1;mode2<=mode1;b2<=b1;
  out_de<=d1;out_hs<=h1;out_vs<=v1;
  out_mask<=(!NATIVE_TEXT && hit1 && text_ink)||g1!=0||card1;
  if(!NATIVE_TEXT && hit1 && text_ink)out_rgb<=mode1==0?(eco?24'h637180:24'h8fcca9):mode1==1?(accent1?24'hffd34d:24'hffffff):mode1==2?(accent1?24'hffb800:24'hffffff):(accent1?24'hffcf73:24'hdce5ed);
  else case(g1)
   1:out_rgb<=b1?24'hff4242:24'hac2631;
   2:out_rgb<=24'hffb800;
   3:out_rgb<=24'h365468;
   4:out_rgb<=24'hffd34d;
   5:out_rgb<=24'h151515;
   default:out_rgb<=PARALLEL?{card_mix(background_p1[23:16],8'd8),card_mix(background_p1[15:8],8'd9),card_mix(background_p1[7:0],8'd11)}:rgb1;
  endcase
 end
end
endmodule
