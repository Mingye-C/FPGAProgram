module widescreen_line_scaler #(parameter DOUBLE=0)(
 input source_clk,source_rst,input source_de,input [23:0] source_rgb,
 output line_space,input output_clk,output_rst,output reg frame_toggle,
 output reg [23:0] rgb,output reg de,sof,eol,
 output reg [31:0] underflow_count,overflow_count,
 output [10:0] output_x,output [9:0] output_y,output reg [10:0] pixel_x,output reg [9:0] pixel_y);
reg [10:0] x;reg [9:0] y;
assign output_x=x;assign output_y=y;
reg [2:0] wp,rp;
(* preserve="true" *)reg [2:0] wg,rg;
(* async_reg="true",preserve="true",keep="true" *) reg [2:0] rg1,rg2,wg1,wg2;
function [2:0] bin;input [2:0] a;begin bin={a[2],a[2]^a[1],a[2]^a[1]^a[0]};end endfunction
wire [2:0] occupied=wp-bin(rg2);
assign line_space=occupied<4;
reg [9:0] write_x;
always @(posedge source_clk or posedge source_rst)begin
 if(source_rst)begin wp<=0;wg<=0;rg1<=0;rg2<=0;write_x<=0;overflow_count<=0;end
 else begin
  rg1<=rg;rg2<=rg1;
  if(source_de)begin
   if(!line_space)overflow_count<=overflow_count+1'b1;
   if(write_x==639)begin write_x<=0;wp<=wp+1'b1;wg<=((wp+3'd1)>>1)^(wp+3'd1);end else write_x<=write_x+1'b1;
  end
 end
end
wire [23:0] q;
reg [9:0] sx;reg [1:0] xp,yp;
wire active=x<1280 && y<720;
wire window=active && (DOUBLE || (x>=160&&x<1120));
wire available=rp!=bin(wg2);
reg [10:0] px1;reg [9:0] py1;
reg line_valid;reg d1,f1,l1,window1,valid1;
line_ram32k u_lines(.wclk(source_clk),.we(source_de&&line_space),.wa({wp[1:0],write_x}),.wd(source_rgb),
 .rclk(output_clk),.ra({rp[1:0],sx}),.rd(q));
always @(posedge output_clk or posedge output_rst)begin
 if(output_rst)begin
  x<=0;y<=720;
  rp<=0;rg<=0;wg1<=0;wg2<=0;frame_toggle<=0;sx<=0;xp<=0;yp<=0;line_valid<=0;
  px1<=0;py1<=0;pixel_x<=0;pixel_y<=720;d1<=0;f1<=0;l1<=0;window1<=0;valid1<=0;rgb<=0;de<=0;sof<=0;eol<=0;underflow_count<=0;
 end else begin
  wg1<=wg;wg2<=wg1;
  if(x==1649)begin x<=0;if(y==749)y<=0;else y<=y+1'b1;end else x<=x+1'b1;
  if(x==0 && y==725)frame_toggle<=~frame_toggle;

  if(x==1649)begin sx<=0;xp<=0;end
  if(x==0)line_valid<=available;
  if(x==(DOUBLE?1:159))begin line_valid<=available;if(y<720 && !available)underflow_count<=underflow_count+1'b1;end
  if(window)begin
   if(DOUBLE)begin xp<=xp==1?0:1;if(xp==1)sx<=sx+1'b1;end
   else begin if(xp==2)xp<=0;else xp<=xp+1'b1;if(xp!=0)sx<=sx+1'b1;end
  end
  if(x==(DOUBLE?1279:1119) && y<720)begin
   if(DOUBLE)begin if(yp==1)begin if(line_valid)begin rp<=rp+1'b1;rg<=((rp+3'd1)>>1)^(rp+3'd1);end yp<=0;end else yp<=1;end
   else begin if(yp!=0 && line_valid)begin rp<=rp+1'b1;rg<=((rp+3'd1)>>1)^(rp+3'd1);end if(yp==2)yp<=0;else yp<=yp+1'b1;end
  end
  if(y==725)yp<=0;
  px1<=x;py1<=y;pixel_x<=px1;pixel_y<=py1;d1<=active;f1<=x==0&&y==0;l1<=x==1279;
  window1<=window;valid1<=x==0?available:line_valid;
  de<=d1;sof<=f1&&d1;eol<=l1&&d1;
  rgb<=window1&&valid1?q:24'd0;
 end
end
endmodule
