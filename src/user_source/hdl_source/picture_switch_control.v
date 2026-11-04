module picture_switch_control #(
 parameter integer TWO_ENCODERS=0,DUAL_MODE_ENABLE=0,ENCODER_ENABLE=0,DEBOUNCE_CYCLES=1_250_000
)(input clk,input rst,input [3:0] switches,input video_vs,
 input encoder_inc,input encoder_dec,input encoder_reset,
 input encoder_single,input encoder_double,
 input contrast_inc,contrast_dec,contrast_reset,
 output reg [3:0] active_code,output reg signed [7:0] brightness,
 output reg [2:0] contrast_q2,output reg change_toggle,
 output reg [8:0] contrast_q8,output reg [3:0] contrast_level,
 output reg adjust_mode,output reg reset_notice);
localparam CW=(DEBOUNCE_CYCLES<2)?1:$clog2(DEBOUNCE_CYCLES);
reg [3:0] sync0,sync1,candidate,stable;
reg [CW-1:0] count;
reg vs_prev;

reg [3:0] accepted_code;
reg [3:0] requested_level,requested_c;
reg requested_mode,requested_reset;
wire [3:0] requested_dual_hi=requested_level-4'd5;
reg pending;
wire [2:0] requested_hi=requested_level-3'd2;
function [8:0] factor_q8;
 input [3:0] idx;
 begin case(idx)
  0:factor_q8=128;1:factor_q8=154;2:factor_q8=179;3:factor_q8=205;
  4:factor_q8=230;5:factor_q8=256;6:factor_q8=282;7:factor_q8=307;
  8:factor_q8=333;9:factor_q8=358;10:factor_q8=384;default:factor_q8=256;
 endcase end
endfunction
reg signed [7:0] mapped_b;
reg [2:0] mapped_c;

always @* begin
 mapped_b=0;mapped_c=4;
 case(stable)
  1:begin mapped_b=-64;mapped_c=3;end
  2:begin mapped_b=-32;mapped_c=3;end
  3:begin mapped_b=0;mapped_c=3;end
  4:begin mapped_b=32;mapped_c=3;end
  5:begin mapped_b=64;mapped_c=3;end
  6:begin mapped_b=-64;mapped_c=4;end
  7:begin mapped_b=-32;mapped_c=4;end
  8:begin mapped_b=0;mapped_c=4;end
  9:begin mapped_b=32;mapped_c=4;end
  10:begin mapped_b=64;mapped_c=4;end
  11:begin mapped_b=-64;mapped_c=5;end
  12:begin mapped_b=-32;mapped_c=5;end
  13:begin mapped_b=0;mapped_c=5;end
  14:begin mapped_b=32;mapped_c=5;end
  15:begin mapped_b=64;mapped_c=5;end
  default:begin mapped_b=0;mapped_c=4;end
 endcase
end
always @(posedge clk or posedge rst) begin
 if(rst)begin
  accepted_code<=0;requested_level<=DUAL_MODE_ENABLE?5:2;requested_c<=DUAL_MODE_ENABLE?5:4;pending<=0;
  requested_mode<=0;requested_reset<=0;adjust_mode<=0;reset_notice<=0;contrast_q8<=256;contrast_level<=5;
  sync0<=0;sync1<=0;candidate<=0;stable<=0;count<=0;
  vs_prev<=0;active_code<=0;brightness<=0;contrast_q2<=4;change_toggle<=0;
 end else begin
  sync0<=switches;sync1<=sync0;vs_prev<=video_vs;

  if(sync1!=candidate)begin candidate<=sync1;count<=0;end
  else if(count<DEBOUNCE_CYCLES-1)count<=count+1'b1;
  else stable<=candidate;
  if(DUAL_MODE_ENABLE)begin
   if(vs_prev && !video_vs && pending)begin
    active_code<=accepted_code;brightness<={requested_dual_hi,4'b0};
    contrast_level<=requested_c;contrast_q8<=factor_q8(requested_c);
    adjust_mode<=requested_mode;reset_notice<=requested_reset;
    change_toggle<=~change_toggle;pending<=0;
   end
   if(stable!=accepted_code || encoder_double || (!TWO_ENCODERS && encoder_single) || (encoder_inc^encoder_dec) || (TWO_ENCODERS && (contrast_reset || (contrast_inc^contrast_dec))))begin
    pending<=1;requested_reset<=0;
    if(stable!=accepted_code)accepted_code<=stable;

    if(encoder_double || (TWO_ENCODERS && contrast_reset))begin requested_level<=5;requested_c<=5;requested_mode<=0;requested_reset<=1;end
    else if(stable!=accepted_code)begin
     requested_level<=mapped_b[7:4]+4'd5;
     case(mapped_c)3:requested_c<=3;5:requested_c<=7;default:requested_c<=5;endcase
    end else if(TWO_ENCODERS)begin
     if(encoder_inc && !encoder_dec && requested_level<10)requested_level<=requested_level+1'b1;
     else if(encoder_dec && !encoder_inc && requested_level>0)requested_level<=requested_level-1'b1;
     if(contrast_inc && !contrast_dec && requested_c<10)requested_c<=requested_c+1'b1;
     else if(contrast_dec && !contrast_inc && requested_c>0)requested_c<=requested_c-1'b1;
     requested_mode<=(contrast_inc^contrast_dec);
    end else if(encoder_single)requested_mode<=~requested_mode;
    else if(requested_mode)begin
     if(encoder_inc && requested_c<10)requested_c<=requested_c+1'b1;
     else if(encoder_dec && requested_c>0)requested_c<=requested_c-1'b1;
    end else begin
     if(encoder_inc && requested_level<10)requested_level<=requested_level+1'b1;
     else if(encoder_dec && requested_level>0)requested_level<=requested_level-1'b1;
    end
   end
  end else if(ENCODER_ENABLE)begin

   if(vs_prev && !video_vs && pending)begin
    active_code<=accepted_code;brightness<={requested_hi,5'b0};contrast_q2<=requested_c;
    change_toggle<=~change_toggle;pending<=0;
   end
   if(stable!=accepted_code)begin
    accepted_code<=stable;requested_c<=mapped_c;pending<=1;
    requested_level<=encoder_reset?3'd2:(mapped_b[7:5]+3'd2);
   end else if(encoder_reset)begin requested_level<=2;pending<=1;end
   else if(encoder_inc ^ encoder_dec)begin
    if(encoder_inc && requested_level<4)requested_level<=requested_level+1'b1;
    else if(encoder_dec && requested_level>0)requested_level<=requested_level-1'b1;
    pending<=1;
   end
  end else if(vs_prev && !video_vs && stable!=active_code)begin
   active_code<=stable;brightness<=mapped_b;contrast_q2<=mapped_c;
   change_toggle<=~change_toggle;
  end
 end
end
endmodule
