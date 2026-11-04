module rgb_picture_adjust #(parameter integer CONTRAST_EXT_ENABLE=0)(
 input clk,input rst,input signed [7:0] brightness,input [2:0] contrast_q2,input [8:0] contrast_q8,
 input [23:0] in_rgb,input in_de,input in_hs,input in_vs,
 output reg [23:0] out_rgb,output reg out_de,output reg out_hs,output reg out_vs);
function signed [11:0] adjust_scaled;
 input [7:0] pixel;
 input signed [7:0] offset;
 input [2:0] factor;
 reg signed [11:0] centered,product,bias;
 begin
  centered=$signed({1'b0,pixel})-12'sd128;
  case(factor)
   3:product=(centered<<<2)-centered;
   5:product=(centered<<<2)+centered;
   default:product=centered<<<2;
  endcase
  bias=(12'sd128+offset)<<<2;
  adjust_scaled=product+bias;
 end
endfunction
function [7:0] saturate;
 input signed [11:0] value;
 begin
  if(value<0)saturate=0;
  else if(value>12'sd1023)saturate=255;
  else saturate=value[9:2];
 end
endfunction
generate if(CONTRAST_EXT_ENABLE)begin: q8_path
 wire signed [8:0] rc=$signed({1'b0,in_rgb[23:16]})-9'sd128;
 wire signed [8:0] gc=$signed({1'b0,in_rgb[15:8]})-9'sd128;
 wire signed [8:0] bc=$signed({1'b0,in_rgb[7:0]})-9'sd128;
 (* use_dsp="yes" *) reg signed [18:0] rp,gp,bp;
 reg signed [18:0] bias;
 reg d0,h0,v0;
 function [7:0] clip_q8;
  input signed [18:0] value;
  begin if(value<0)clip_q8=0;else if(value>19'sd65535)clip_q8=255;else clip_q8=value[15:8];end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin rp<=0;gp<=0;bp<=0;bias<=0;d0<=0;h0<=0;v0<=0;out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;end
  else begin
   rp<=rc*$signed({1'b0,contrast_q8});
   gp<=gc*$signed({1'b0,contrast_q8});
   bp<=bc*$signed({1'b0,contrast_q8});
   bias<=((19'sd128+$signed(brightness))<<<8)+19'sd128;
   d0<=in_de;h0<=in_hs;v0<=in_vs;
   out_rgb<={clip_q8(rp+bias),clip_q8(gp+bias),clip_q8(bp+bias)};
   out_de<=d0;out_hs<=h0;out_vs<=v0;
  end
 end
end else begin: legacy_path
reg signed [11:0] r0,g0,b0;
reg d0,h0,v0;
always @(posedge clk or posedge rst)begin
 if(rst)begin r0<=0;g0<=0;b0<=0;d0<=0;h0<=0;v0<=0;out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;end
 else begin
  r0<=adjust_scaled(in_rgb[23:16],brightness,contrast_q2);
  g0<=adjust_scaled(in_rgb[15:8],brightness,contrast_q2);
  b0<=adjust_scaled(in_rgb[7:0],brightness,contrast_q2);
  d0<=in_de;h0<=in_hs;v0<=in_vs;
  out_rgb<={saturate(r0),saturate(g0),saturate(b0)};
  out_de<=d0;out_hs<=h0;out_vs<=v0;
 end
end
end endgenerate
endmodule
