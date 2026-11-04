module scrolling_subtitle #(
    parameter integer VIDEO_WIDTH = 640,
    parameter integer VIDEO_HEIGHT = 480,
    parameter integer CLIP_X = 0,
    parameter integer CLIP_WIDTH = VIDEO_WIDTH,
    parameter integer TEXT_Y = VIDEO_HEIGHT-40,
    parameter integer TEXT_LEN = 41,
    parameter SCENE_ENABLE=0,EXTERNAL_FONT_ENABLE=0,NATIVE_TEXT=0,
    parameter CHINESE_ENABLE = 1'b1,
    parameter [TEXT_LEN*8-1:0] TEXT = "WELCOME TO FPGA MULTIMEDIA DISPLAY SYSTEM",
    parameter [23:0] FG_COLOR = 24'hffffff,
    parameter SHADOW_ENABLE = 1'b1,
    parameter [23:0] SHADOW_COLOR = 24'h000000,
    parameter integer FRAMES_PER_STEP = 1,
    parameter integer STEP_PIXELS = 1
)(
    output [10:0] native_phase,output native_chinese,
    input clk, input rst, input enable,input [1:0] scene_mode,
    output [12:0] font_a_request,font_b_request,
    output [14:0] chinese_a_request,chinese_b_request,
    output [10:0] text_a_request,text_b_request,input [7:0] external_text_a,external_text_b,
    input [7:0] external_font_a,external_font_b,input external_chinese_a,external_chinese_b,
    input [23:0] in_rgb, input in_de, input in_hs, input in_vs,
    output reg [23:0] out_rgb,
    output reg out_de, output reg out_hs, output reg out_vs
);
wire [1:0] scene=SCENE_ENABLE?scene_mode:2'd0;
localparam integer ENGLISH_WIDTH=TEXT_LEN*8,RIGHT_EDGE=CLIP_X+CLIP_WIDTH;
localparam integer MAX_WIDTH=ENGLISH_WIDTH>568?ENGLISH_WIDTH:568;
localparam integer PHASE_BITS=$clog2(CLIP_WIDTH+MAX_WIDTH+2);
localparam integer POS_BITS=$clog2(VIDEO_WIDTH+CLIP_WIDTH+MAX_WIDTH+4);
reg chinese_active;reg [1:0] scene_previous;
reg de_prev,vs_prev;reg [$clog2(VIDEO_WIDTH+1)-1:0] x_count;
reg [$clog2(VIDEO_HEIGHT+1)-1:0] y_count;
reg [PHASE_BITS-1:0] scroll_phase;reg [31:0] frame_div;
wire frame_tick=vs_prev && !in_vs;
assign native_phase=scroll_phase;assign native_chinese=chinese_active;
function [6:0] english_length;input [1:0] mode;begin case(mode)
0:english_length=TEXT_LEN;
1:english_length=7'd36;
2:english_length=7'd16;
3:english_length=7'd14;
endcase end endfunction
function [6:0] chinese_length;input [1:0] mode;begin case(mode)
0:chinese_length=7'd16;
1:chinese_length=7'd16;
2:chinese_length=7'd14;
3:chinese_length=7'd19;
endcase end endfunction
function [7:0] english_char;input [1:0] mode;input [7:0] index;reg [327:0] message;reg [6:0] n;begin
 n=english_length(mode);case(mode)
0:message=TEXT;
1:message="FIRE EMERGENCY! DO NOT USE ELEVATOR!";
2:message="OVERLOAD WARNING";
3:message="OUT OF SERVICE";
endcase
 english_char=index<n?message[(n-1-index)*8 +:8]:8'd32;end endfunction
function [7:0] chinese_char;input [1:0] mode;input [7:0] index;reg [151:0] message;reg [6:0] n;begin
 n=chinese_length(mode);case(mode)
0:message=152'h808182838485868788898a82868b8c8d;
1:message=152'h8e8f9091b188928286b188938b8c9495;
2:message=152'h96979899b1889a9b829c9d9e9fa0;
3:message=152'ha1a2a3a4b1a5a6a7a8b1a9aaabacb1ad88aeaf;
endcase
 chinese_char=index<n?message[(n-1-index)*8 +:8]:8'd177;end endfunction

wire [PHASE_BITS-1:0] ew={english_length(scene),3'b0};
wire [PHASE_BITS-1:0] cw={chinese_length(scene),4'b0};
wire [PHASE_BITS-1:0] text_width=scene==0?(chinese_active?256:ENGLISH_WIDTH):(ew+24+cw);
wire [PHASE_BITS-1:0] scroll_end=(NATIVE_TEXT && scene==0)?895:CLIP_WIDTH+text_width+(SHADOW_ENABLE?1:0);
wire [POS_BITS-1:0] local_x=x_count+scroll_phase-RIGHT_EDGE;
wire [POS_BITS-1:0] shadow_x=local_x-1'b1;
wire clipped=enable && in_de && x_count>=CLIP_X && x_count<RIGHT_EDGE;
wire glyph_hit=clipped && y_count>=TEXT_Y && y_count<TEXT_Y+16 && local_x<text_width;
wire shadow_hit=SHADOW_ENABLE && clipped && y_count>=TEXT_Y+1 && y_count<TEXT_Y+17 && shadow_x<text_width;
function [11:0] descriptor;
 input [POS_BITS-1:0] pos;reg [POS_BITS-1:0] t;reg [7:0] c;
 begin
  t=pos;c=32;
  if(scene==0)begin
   if(chinese_active)begin c=chinese_char(0,pos>>4);descriptor={c,pos[3:0]};end
   else begin c=english_char(0,pos>>3);descriptor={c,1'b0,pos[2:0]};end
  end else if(pos<ew)begin c=english_char(scene,pos>>3);descriptor={c,1'b0,pos[2:0]};end
  else if(pos<ew+24)begin t=pos-ew;c=(t[4:3]==1)?8'd47:8'd32;descriptor={c,1'b0,t[2:0]};end
  else begin t=pos-ew-24;c=chinese_char(scene,t>>4);descriptor={c,t[3:0]};end
 end
endfunction
wire [11:0] current=descriptor(local_x),shade=descriptor(shadow_x);

function [14:0] map_descriptor;
 input [POS_BITS-1:0] pos;reg [POS_BITS-1:0] t;reg [9:0] base;reg cn;
 begin
  t=pos;base=672;cn=0;
  if(scene==0)begin if(chinese_active)begin base=736;cn=1;end end
  else if(pos<ew)begin case(scene)1:base=752;2:base=788;default:base=804;endcase end
  else if(pos<ew+24)begin t=pos-ew;base=900;end
  else begin
   t=pos-ew-24;cn=1;
   case(scene)1:base=818;2:base=834;default:base=848;endcase
  end
  map_descriptor=0;map_descriptor[14]=cn;
  map_descriptor[13:4]=base+(cn?(t>>4):(t>>3));
  map_descriptor[3:0]=cn?t[3:0]:{1'b0,t[2:0]};
 end
endfunction
wire [14:0] map_a=map_descriptor(local_x),map_b=map_descriptor(shadow_x);
assign text_a_request={glyph_hit,map_a[13:4]};
assign text_b_request={shadow_hit,map_b[13:4]};
wire [7:0] char_at0=EXTERNAL_FONT_ENABLE?external_text_a:char_p0;
wire [7:0] shadow_at0=EXTERNAL_FONT_ENABLE?external_text_b:shadow_char_p0;

reg [23:0] rgb_p0,rgb_p1;
reg de_p0,hs_p0,vs_p0,glyph_p0,shadow_p0;
reg de_p1,hs_p1,vs_p1,glyph_p1,shadow_p1;
reg [7:0] char_p0,shadow_char_p0;reg [3:0] row_p0,shadow_row_p0;
reg [13:0] cn_addr_p0,cn_shadow_addr_p0;reg cn_p0,cn_p1,shadow_cn_p0,shadow_cn_p1;
wire [7:0] font_p1,shadow_font_p1;wire cn_font_p1,cn_shadow_font_p1;
reg [2:0] col_p0,col_p1,shadow_col_p0,shadow_col_p1;
wire [3:0] glyph_row=y_count-TEXT_Y,shadow_row=y_count-TEXT_Y-1;
generate if(EXTERNAL_FONT_ENABLE)begin
 assign font_p1=external_font_a;assign shadow_font_p1=external_font_b;
 assign cn_font_p1=external_chinese_a;assign cn_shadow_font_p1=external_chinese_b;
end else begin
 subtitle_compact_rom u_font(.clk(clk),.a(char_p0),.ar(row_p0),.b(shadow_char_p0),.br(shadow_row_p0),.ap(font_p1),.bp(shadow_font_p1));
 subtitle_chinese_pixel_rom u_cn_font(.clk(clk),.a(cn_addr_p0[11:0]),.b(cn_shadow_addr_p0[11:0]),.ap(cn_font_p1),.bp(cn_shadow_font_p1));
end endgenerate
assign font_a_request={glyph_p0 && !cn_p0,char_at0,row_p0};
assign font_b_request={shadow_p0 && !shadow_cn_p0,shadow_at0,shadow_row_p0};
assign chinese_a_request={glyph_p0 && cn_p0,(EXTERNAL_FONT_ENABLE?{char_at0[5:0],row_p0,cn_addr_p0[3:0]}:cn_addr_p0)};
assign chinese_b_request={shadow_p0 && shadow_cn_p0,(EXTERNAL_FONT_ENABLE?{shadow_at0[5:0],shadow_row_p0,cn_shadow_addr_p0[3:0]}:cn_shadow_addr_p0)};
always @(posedge clk or posedge rst)begin
 if(rst)begin de_prev<=0;vs_prev<=0;x_count<=0;y_count<=0;scroll_phase<=0;frame_div<=0;chinese_active<=0;scene_previous<=0;end
 else begin
  de_prev<=in_de;vs_prev<=in_vs;
  if(frame_tick)begin
   x_count<=0;y_count<=0;scene_previous<=scene;
   if(scene!=scene_previous)begin scroll_phase<=0;frame_div<=0;chinese_active<=0;end
   else if(frame_div >= (scene==3?2*FRAMES_PER_STEP:FRAMES_PER_STEP)-1)begin
    frame_div<=0;
    if(scroll_phase>=scroll_end)begin scroll_phase<=0;if(scene==0 && CHINESE_ENABLE)chinese_active<=!chinese_active;end
    else if(scroll_phase+(scene==1?2*STEP_PIXELS:STEP_PIXELS)>=scroll_end)scroll_phase<=scroll_end;
    else scroll_phase<=scroll_phase+(scene==1?2*STEP_PIXELS:STEP_PIXELS);
   end else frame_div<=frame_div+1'b1;
  end else begin
   if(in_de)x_count<=x_count+1'b1;else x_count<=0;
   if(de_prev && !in_de && y_count<VIDEO_HEIGHT)y_count<=y_count+1'b1;
  end
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  rgb_p0<=0;rgb_p1<=0;out_rgb<=0;de_p0<=0;hs_p0<=0;vs_p0<=0;glyph_p0<=0;shadow_p0<=0;
  de_p1<=0;hs_p1<=0;vs_p1<=0;glyph_p1<=0;shadow_p1<=0;out_de<=0;out_hs<=0;out_vs<=0;
  char_p0<=32;shadow_char_p0<=32;row_p0<=0;shadow_row_p0<=0;cn_addr_p0<=0;cn_shadow_addr_p0<=0;
  cn_p0<=0;cn_p1<=0;shadow_cn_p0<=0;shadow_cn_p1<=0;col_p0<=0;col_p1<=0;shadow_col_p0<=0;shadow_col_p1<=0;
 end else begin
  rgb_p0<=in_rgb;de_p0<=in_de;hs_p0<=in_hs;vs_p0<=in_vs;glyph_p0<=glyph_hit;shadow_p0<=shadow_hit;
  char_p0<=current[11:4];shadow_char_p0<=shade[11:4];row_p0<=glyph_row;shadow_row_p0<=shadow_row;
  cn_addr_p0<=EXTERNAL_FONT_ENABLE?{6'd0,glyph_row,map_a[3:0]}:{current[9:4],glyph_row,current[3:0]};cn_shadow_addr_p0<=EXTERNAL_FONT_ENABLE?{6'd0,shadow_row,map_b[3:0]}:{shade[9:4],shadow_row,shade[3:0]};
  cn_p0<=EXTERNAL_FONT_ENABLE?map_a[14]:current[11];shadow_cn_p0<=EXTERNAL_FONT_ENABLE?map_b[14]:shade[11];cn_p1<=cn_p0;shadow_cn_p1<=shadow_cn_p0;
  col_p0<=EXTERNAL_FONT_ENABLE?map_a[2:0]:current[2:0];shadow_col_p0<=EXTERNAL_FONT_ENABLE?map_b[2:0]:shade[2:0];
  rgb_p1<=rgb_p0;de_p1<=de_p0;hs_p1<=hs_p0;vs_p1<=vs_p0;glyph_p1<=glyph_p0;shadow_p1<=shadow_p0;
  col_p1<=col_p0;shadow_col_p1<=shadow_col_p0;
  out_de<=de_p1;out_hs<=hs_p1;out_vs<=vs_p1;
  if(!NATIVE_TEXT && glyph_p1 && (cn_p1?cn_font_p1:font_p1[7-col_p1]))out_rgb<=scene==1?24'hffd34d:scene==2?24'hffb800:scene==3?24'hc9d3df:FG_COLOR;
  else if(!NATIVE_TEXT && shadow_p1 && (shadow_cn_p1?cn_shadow_font_p1:shadow_font_p1[7-shadow_col_p1]))out_rgb<=SHADOW_COLOR;
  else out_rgb<=rgb_p1;
 end
end
endmodule

module subtitle_compact_rom(input clk,input [7:0] a,b,input [3:0] ar,br,output [7:0] ap,bp);
(* ram_style="block" *) reg [4:0] rows[0:1023];integer i;
wire [6:0] ca=(a>=32 && a<=126)?a[6:0]:7'd63;
wire [6:0] cb=(b>=32 && b<=126)?b[6:0]:7'd63;
wire [3:0] ay=ar-1'b1,by=br-1'b1;
reg [4:0] aq,bq;reg av,bv;
initial begin
 for(i=0;i<1024;i=i+1)rows[i]=0;
 rows[264]=5'd4;
 rows[265]=5'd4;
 rows[266]=5'd4;
 rows[267]=5'd4;
 rows[268]=5'd4;
 rows[270]=5'd4;
 rows[272]=5'd10;
 rows[273]=5'd10;
 rows[274]=5'd10;
 rows[280]=5'd10;
 rows[281]=5'd10;
 rows[282]=5'd31;
 rows[283]=5'd10;
 rows[284]=5'd31;
 rows[285]=5'd10;
 rows[286]=5'd10;
 rows[288]=5'd4;
 rows[289]=5'd15;
 rows[290]=5'd20;
 rows[291]=5'd14;
 rows[292]=5'd5;
 rows[293]=5'd30;
 rows[294]=5'd4;
 rows[296]=5'd24;
 rows[297]=5'd25;
 rows[298]=5'd1;
 rows[299]=5'd2;
 rows[300]=5'd4;
 rows[301]=5'd19;
 rows[302]=5'd3;
 rows[304]=5'd12;
 rows[305]=5'd18;
 rows[306]=5'd20;
 rows[307]=5'd8;
 rows[308]=5'd21;
 rows[309]=5'd18;
 rows[310]=5'd13;
 rows[312]=5'd4;
 rows[313]=5'd4;
 rows[314]=5'd8;
 rows[320]=5'd2;
 rows[321]=5'd4;
 rows[322]=5'd8;
 rows[323]=5'd8;
 rows[324]=5'd8;
 rows[325]=5'd4;
 rows[326]=5'd2;
 rows[328]=5'd8;
 rows[329]=5'd4;
 rows[330]=5'd2;
 rows[331]=5'd2;
 rows[332]=5'd2;
 rows[333]=5'd4;
 rows[334]=5'd8;
 rows[337]=5'd10;
 rows[338]=5'd4;
 rows[339]=5'd31;
 rows[340]=5'd4;
 rows[341]=5'd10;
 rows[345]=5'd4;
 rows[346]=5'd4;
 rows[347]=5'd31;
 rows[348]=5'd4;
 rows[349]=5'd4;
 rows[357]=5'd4;
 rows[358]=5'd8;
 rows[363]=5'd31;
 rows[374]=5'd4;
 rows[376]=5'd1;
 rows[377]=5'd1;
 rows[378]=5'd2;
 rows[379]=5'd4;
 rows[380]=5'd8;
 rows[381]=5'd16;
 rows[382]=5'd16;
 rows[384]=5'd14;
 rows[385]=5'd17;
 rows[386]=5'd19;
 rows[387]=5'd21;
 rows[388]=5'd25;
 rows[389]=5'd17;
 rows[390]=5'd14;
 rows[392]=5'd4;
 rows[393]=5'd12;
 rows[394]=5'd4;
 rows[395]=5'd4;
 rows[396]=5'd4;
 rows[397]=5'd4;
 rows[398]=5'd14;
 rows[400]=5'd14;
 rows[401]=5'd17;
 rows[402]=5'd1;
 rows[403]=5'd2;
 rows[404]=5'd4;
 rows[405]=5'd8;
 rows[406]=5'd31;
 rows[408]=5'd30;
 rows[409]=5'd1;
 rows[410]=5'd1;
 rows[411]=5'd6;
 rows[412]=5'd1;
 rows[413]=5'd1;
 rows[414]=5'd30;
 rows[416]=5'd2;
 rows[417]=5'd6;
 rows[418]=5'd10;
 rows[419]=5'd18;
 rows[420]=5'd31;
 rows[421]=5'd2;
 rows[422]=5'd2;
 rows[424]=5'd31;
 rows[425]=5'd16;
 rows[426]=5'd16;
 rows[427]=5'd30;
 rows[428]=5'd1;
 rows[429]=5'd1;
 rows[430]=5'd30;
 rows[432]=5'd14;
 rows[433]=5'd16;
 rows[434]=5'd16;
 rows[435]=5'd30;
 rows[436]=5'd17;
 rows[437]=5'd17;
 rows[438]=5'd14;
 rows[440]=5'd31;
 rows[441]=5'd1;
 rows[442]=5'd2;
 rows[443]=5'd4;
 rows[444]=5'd8;
 rows[445]=5'd8;
 rows[446]=5'd8;
 rows[448]=5'd14;
 rows[449]=5'd17;
 rows[450]=5'd17;
 rows[451]=5'd14;
 rows[452]=5'd17;
 rows[453]=5'd17;
 rows[454]=5'd14;
 rows[456]=5'd14;
 rows[457]=5'd17;
 rows[458]=5'd17;
 rows[459]=5'd15;
 rows[460]=5'd1;
 rows[461]=5'd1;
 rows[462]=5'd14;
 rows[466]=5'd4;
 rows[469]=5'd4;
 rows[474]=5'd4;
 rows[477]=5'd4;
 rows[478]=5'd8;
 rows[480]=5'd1;
 rows[481]=5'd2;
 rows[482]=5'd4;
 rows[483]=5'd8;
 rows[484]=5'd4;
 rows[485]=5'd2;
 rows[486]=5'd1;
 rows[490]=5'd31;
 rows[492]=5'd31;
 rows[496]=5'd16;
 rows[497]=5'd8;
 rows[498]=5'd4;
 rows[499]=5'd2;
 rows[500]=5'd4;
 rows[501]=5'd8;
 rows[502]=5'd16;
 rows[504]=5'd14;
 rows[505]=5'd17;
 rows[506]=5'd1;
 rows[507]=5'd2;
 rows[508]=5'd4;
 rows[510]=5'd4;
 rows[512]=5'd14;
 rows[513]=5'd17;
 rows[514]=5'd23;
 rows[515]=5'd21;
 rows[516]=5'd23;
 rows[517]=5'd16;
 rows[518]=5'd14;
 rows[520]=5'd14;
 rows[521]=5'd17;
 rows[522]=5'd17;
 rows[523]=5'd31;
 rows[524]=5'd17;
 rows[525]=5'd17;
 rows[526]=5'd17;
 rows[528]=5'd30;
 rows[529]=5'd17;
 rows[530]=5'd17;
 rows[531]=5'd30;
 rows[532]=5'd17;
 rows[533]=5'd17;
 rows[534]=5'd30;
 rows[536]=5'd14;
 rows[537]=5'd17;
 rows[538]=5'd16;
 rows[539]=5'd16;
 rows[540]=5'd16;
 rows[541]=5'd17;
 rows[542]=5'd14;
 rows[544]=5'd30;
 rows[545]=5'd17;
 rows[546]=5'd17;
 rows[547]=5'd17;
 rows[548]=5'd17;
 rows[549]=5'd17;
 rows[550]=5'd30;
 rows[552]=5'd31;
 rows[553]=5'd16;
 rows[554]=5'd16;
 rows[555]=5'd30;
 rows[556]=5'd16;
 rows[557]=5'd16;
 rows[558]=5'd31;
 rows[560]=5'd31;
 rows[561]=5'd16;
 rows[562]=5'd16;
 rows[563]=5'd30;
 rows[564]=5'd16;
 rows[565]=5'd16;
 rows[566]=5'd16;
 rows[568]=5'd14;
 rows[569]=5'd17;
 rows[570]=5'd16;
 rows[571]=5'd23;
 rows[572]=5'd17;
 rows[573]=5'd17;
 rows[574]=5'd15;
 rows[576]=5'd17;
 rows[577]=5'd17;
 rows[578]=5'd17;
 rows[579]=5'd31;
 rows[580]=5'd17;
 rows[581]=5'd17;
 rows[582]=5'd17;
 rows[584]=5'd14;
 rows[585]=5'd4;
 rows[586]=5'd4;
 rows[587]=5'd4;
 rows[588]=5'd4;
 rows[589]=5'd4;
 rows[590]=5'd14;
 rows[592]=5'd7;
 rows[593]=5'd2;
 rows[594]=5'd2;
 rows[595]=5'd2;
 rows[596]=5'd2;
 rows[597]=5'd18;
 rows[598]=5'd12;
 rows[600]=5'd17;
 rows[601]=5'd18;
 rows[602]=5'd20;
 rows[603]=5'd24;
 rows[604]=5'd20;
 rows[605]=5'd18;
 rows[606]=5'd17;
 rows[608]=5'd16;
 rows[609]=5'd16;
 rows[610]=5'd16;
 rows[611]=5'd16;
 rows[612]=5'd16;
 rows[613]=5'd16;
 rows[614]=5'd31;
 rows[616]=5'd17;
 rows[617]=5'd27;
 rows[618]=5'd21;
 rows[619]=5'd21;
 rows[620]=5'd17;
 rows[621]=5'd17;
 rows[622]=5'd17;
 rows[624]=5'd17;
 rows[625]=5'd25;
 rows[626]=5'd21;
 rows[627]=5'd19;
 rows[628]=5'd17;
 rows[629]=5'd17;
 rows[630]=5'd17;
 rows[632]=5'd14;
 rows[633]=5'd17;
 rows[634]=5'd17;
 rows[635]=5'd17;
 rows[636]=5'd17;
 rows[637]=5'd17;
 rows[638]=5'd14;
 rows[640]=5'd30;
 rows[641]=5'd17;
 rows[642]=5'd17;
 rows[643]=5'd30;
 rows[644]=5'd16;
 rows[645]=5'd16;
 rows[646]=5'd16;
 rows[648]=5'd14;
 rows[649]=5'd17;
 rows[650]=5'd17;
 rows[651]=5'd17;
 rows[652]=5'd21;
 rows[653]=5'd18;
 rows[654]=5'd13;
 rows[656]=5'd30;
 rows[657]=5'd17;
 rows[658]=5'd17;
 rows[659]=5'd30;
 rows[660]=5'd20;
 rows[661]=5'd18;
 rows[662]=5'd17;
 rows[664]=5'd15;
 rows[665]=5'd16;
 rows[666]=5'd16;
 rows[667]=5'd14;
 rows[668]=5'd1;
 rows[669]=5'd1;
 rows[670]=5'd30;
 rows[672]=5'd31;
 rows[673]=5'd4;
 rows[674]=5'd4;
 rows[675]=5'd4;
 rows[676]=5'd4;
 rows[677]=5'd4;
 rows[678]=5'd4;
 rows[680]=5'd17;
 rows[681]=5'd17;
 rows[682]=5'd17;
 rows[683]=5'd17;
 rows[684]=5'd17;
 rows[685]=5'd17;
 rows[686]=5'd14;
 rows[688]=5'd17;
 rows[689]=5'd17;
 rows[690]=5'd17;
 rows[691]=5'd17;
 rows[692]=5'd17;
 rows[693]=5'd10;
 rows[694]=5'd4;
 rows[696]=5'd17;
 rows[697]=5'd17;
 rows[698]=5'd17;
 rows[699]=5'd21;
 rows[700]=5'd21;
 rows[701]=5'd27;
 rows[702]=5'd17;
 rows[704]=5'd17;
 rows[705]=5'd17;
 rows[706]=5'd10;
 rows[707]=5'd4;
 rows[708]=5'd10;
 rows[709]=5'd17;
 rows[710]=5'd17;
 rows[712]=5'd17;
 rows[713]=5'd17;
 rows[714]=5'd10;
 rows[715]=5'd4;
 rows[716]=5'd4;
 rows[717]=5'd4;
 rows[718]=5'd4;
 rows[720]=5'd31;
 rows[721]=5'd1;
 rows[722]=5'd2;
 rows[723]=5'd4;
 rows[724]=5'd8;
 rows[725]=5'd16;
 rows[726]=5'd31;
 rows[728]=5'd14;
 rows[729]=5'd8;
 rows[730]=5'd8;
 rows[731]=5'd8;
 rows[732]=5'd8;
 rows[733]=5'd8;
 rows[734]=5'd14;
 rows[736]=5'd16;
 rows[737]=5'd16;
 rows[738]=5'd8;
 rows[739]=5'd4;
 rows[740]=5'd2;
 rows[741]=5'd1;
 rows[742]=5'd1;
 rows[744]=5'd14;
 rows[745]=5'd2;
 rows[746]=5'd2;
 rows[747]=5'd2;
 rows[748]=5'd2;
 rows[749]=5'd2;
 rows[750]=5'd14;
 rows[752]=5'd4;
 rows[753]=5'd10;
 rows[754]=5'd17;
 rows[766]=5'd31;
 rows[768]=5'd8;
 rows[769]=5'd4;
 rows[770]=5'd2;
 rows[778]=5'd14;
 rows[779]=5'd1;
 rows[780]=5'd15;
 rows[781]=5'd17;
 rows[782]=5'd15;
 rows[784]=5'd16;
 rows[785]=5'd16;
 rows[786]=5'd22;
 rows[787]=5'd25;
 rows[788]=5'd17;
 rows[789]=5'd17;
 rows[790]=5'd30;
 rows[794]=5'd14;
 rows[795]=5'd17;
 rows[796]=5'd16;
 rows[797]=5'd17;
 rows[798]=5'd14;
 rows[800]=5'd1;
 rows[801]=5'd1;
 rows[802]=5'd13;
 rows[803]=5'd19;
 rows[804]=5'd17;
 rows[805]=5'd17;
 rows[806]=5'd15;
 rows[810]=5'd14;
 rows[811]=5'd17;
 rows[812]=5'd31;
 rows[813]=5'd16;
 rows[814]=5'd14;
 rows[816]=5'd6;
 rows[817]=5'd9;
 rows[818]=5'd8;
 rows[819]=5'd28;
 rows[820]=5'd8;
 rows[821]=5'd8;
 rows[822]=5'd8;
 rows[826]=5'd15;
 rows[827]=5'd17;
 rows[828]=5'd17;
 rows[829]=5'd15;
 rows[830]=5'd1;
 rows[832]=5'd16;
 rows[833]=5'd16;
 rows[834]=5'd22;
 rows[835]=5'd25;
 rows[836]=5'd17;
 rows[837]=5'd17;
 rows[838]=5'd17;
 rows[840]=5'd4;
 rows[842]=5'd12;
 rows[843]=5'd4;
 rows[844]=5'd4;
 rows[845]=5'd4;
 rows[846]=5'd14;
 rows[848]=5'd2;
 rows[850]=5'd6;
 rows[851]=5'd2;
 rows[852]=5'd2;
 rows[853]=5'd18;
 rows[854]=5'd12;
 rows[856]=5'd16;
 rows[857]=5'd16;
 rows[858]=5'd17;
 rows[859]=5'd18;
 rows[860]=5'd28;
 rows[861]=5'd18;
 rows[862]=5'd17;
 rows[864]=5'd12;
 rows[865]=5'd4;
 rows[866]=5'd4;
 rows[867]=5'd4;
 rows[868]=5'd4;
 rows[869]=5'd4;
 rows[870]=5'd14;
 rows[874]=5'd26;
 rows[875]=5'd21;
 rows[876]=5'd21;
 rows[877]=5'd21;
 rows[878]=5'd21;
 rows[882]=5'd22;
 rows[883]=5'd25;
 rows[884]=5'd17;
 rows[885]=5'd17;
 rows[886]=5'd17;
 rows[890]=5'd14;
 rows[891]=5'd17;
 rows[892]=5'd17;
 rows[893]=5'd17;
 rows[894]=5'd14;
 rows[898]=5'd30;
 rows[899]=5'd17;
 rows[900]=5'd17;
 rows[901]=5'd30;
 rows[902]=5'd16;
 rows[906]=5'd15;
 rows[907]=5'd17;
 rows[908]=5'd17;
 rows[909]=5'd15;
 rows[910]=5'd1;
 rows[914]=5'd22;
 rows[915]=5'd25;
 rows[916]=5'd16;
 rows[917]=5'd16;
 rows[918]=5'd16;
 rows[922]=5'd15;
 rows[923]=5'd16;
 rows[924]=5'd14;
 rows[925]=5'd1;
 rows[926]=5'd30;
 rows[928]=5'd8;
 rows[929]=5'd8;
 rows[930]=5'd28;
 rows[931]=5'd8;
 rows[932]=5'd8;
 rows[933]=5'd9;
 rows[934]=5'd6;
 rows[938]=5'd17;
 rows[939]=5'd17;
 rows[940]=5'd17;
 rows[941]=5'd19;
 rows[942]=5'd13;
 rows[946]=5'd17;
 rows[947]=5'd17;
 rows[948]=5'd17;
 rows[949]=5'd10;
 rows[950]=5'd4;
 rows[954]=5'd17;
 rows[955]=5'd17;
 rows[956]=5'd21;
 rows[957]=5'd21;
 rows[958]=5'd10;
 rows[962]=5'd17;
 rows[963]=5'd10;
 rows[964]=5'd4;
 rows[965]=5'd10;
 rows[966]=5'd17;
 rows[970]=5'd17;
 rows[971]=5'd17;
 rows[972]=5'd17;
 rows[973]=5'd15;
 rows[974]=5'd1;
 rows[978]=5'd31;
 rows[979]=5'd2;
 rows[980]=5'd4;
 rows[981]=5'd8;
 rows[982]=5'd31;
 rows[984]=5'd2;
 rows[985]=5'd4;
 rows[986]=5'd4;
 rows[987]=5'd8;
 rows[988]=5'd4;
 rows[989]=5'd4;
 rows[990]=5'd2;
 rows[992]=5'd4;
 rows[993]=5'd4;
 rows[994]=5'd4;
 rows[995]=5'd4;
 rows[996]=5'd4;
 rows[997]=5'd4;
 rows[998]=5'd4;
 rows[1000]=5'd8;
 rows[1001]=5'd4;
 rows[1002]=5'd4;
 rows[1003]=5'd2;
 rows[1004]=5'd4;
 rows[1005]=5'd4;
 rows[1006]=5'd8;
 rows[1010]=5'd8;
 rows[1011]=5'd21;
 rows[1012]=5'd2;
end
always @(posedge clk)begin
 aq<=rows[{ca,ay[3:1]}];bq<=rows[{cb,by[3:1]}];
 av<=ar!=0 && ar!=15;bv<=br!=0 && br!=15;
end
assign ap=av?{1'b0,aq,2'b0}:8'd0;
assign bp=bv?{1'b0,bq,2'b0}:8'd0;
endmodule
