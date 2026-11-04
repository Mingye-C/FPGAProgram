module eco_radar_circle #(parameter STYLE=1)(
 input clk,input rst,input frame_tick,input [6:0] phase,
 input [9:0] x,input [8:0] y,
 output hit,output [23:0] color,output ready);
localparam NBOUND=STYLE==1?6:STYLE==2?2:4;
reg [6:0] phase_q;
reg busy,valid,initialized;
reg [2:0] index,product_index;
reg [15:0] lower0,upper0,lower1,upper1,lower2,upper2;
reg [15:0] bound_square;
reg [6:0] p;
reg [7:0] radius,bound;
wire [5:0] triangle=phase_q[6]?~phase_q[5:0]:phase_q[5:0];
always @*begin
 p=phase_q;radius=0;bound=0;
 if(STYLE==1)begin
  case(index[2:1])1:p=phase_q+7'd43;2:p=phase_q+7'd86;default:p=phase_q;endcase
  radius=8'd24+{1'b0,p}+{2'b0,p[6:1]};
  bound=index[0]?radius+1'b1:radius-1'b1;
 end else if(STYLE==2)begin
  radius=8'd48+{2'd0,triangle}+{3'd0,triangle[5:1]};
  bound=index[0]?radius+1'b1:radius-1'b1;
 end else begin
  radius=index[1]?8'd112+{2'd0,triangle}:8'd44+{3'd0,triangle[5:1]};
  if(index[1])bound=index[0]?radius+1'b1:radius-1'b1;
  else bound=index[0]?radius+2'd2:radius-2'd2;
 end
end
(* use_dsp="yes" *) wire [15:0] bound_product=bound*bound;
assign ready=initialized;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  phase_q<=0;busy<=0;valid<=0;initialized<=0;index<=0;product_index<=0;
  bound_square<=0;lower0<=0;upper0<=0;lower1<=0;upper1<=0;lower2<=0;upper2<=0;
 end else begin
  valid<=0;

  if(frame_tick || (!initialized && !busy && !valid))begin phase_q<=phase;busy<=1;index<=0;end
  else if(busy)begin
   bound_square<=bound_product;product_index<=index;valid<=1;
   if(index==NBOUND-1)busy<=0;else index<=index+1'b1;
  end
  if(valid)begin

   lower0<=upper0;
   if(STYLE==2)upper0<=bound_square;
   else begin
    upper0<=lower1;lower1<=upper1;
    if(STYLE==3)upper1<=bound_square;
    else begin upper1<=lower2;lower2<=upper2;upper2<=bound_square;end
   end
   if(product_index==NBOUND-1)initialized<=1;
  end
 end
end
wire [9:0] ax=x>=395?x-10'd395:10'd395-x;
wire [8:0] ay=y>=180?y-9'd180:9'd180-y;
reg [7:0] dx0,dy0;reg dash0,dash1,cross0,cross1;
reg [16:0] distance1;
reg [1:0] breath1;
wire [5:0] tri_now=phase_q[6]?~phase_q[5:0]:phase_q[5:0];
(* use_dsp="yes" *) wire [15:0] square_x=dx0*dx0,square_y=dy0*dy0;
always @(posedge clk or posedge rst)begin
 if(rst)begin dx0<=0;dy0<=0;distance1<=0;dash0<=0;dash1<=0;cross0<=0;cross1<=0;breath1<=0;end
 else begin

  dx0<=ax[7:0];dy0<=ay[7:0];
  distance1<={1'b0,square_x}+{1'b0,square_y};
  dash0<=x[4]^y[4];dash1<=dash0;
  cross0<=(ax<=5 && ay==0)||(ay<=5 && ax==0);cross1<=cross0;
  breath1<=tri_now[5:4];
 end
end
wire ring0=initialized && !distance1[16] && distance1[15:0]>=lower0 && distance1[15:0]<upper0;
wire ring1=initialized && !distance1[16] && distance1[15:0]>=lower1 && distance1[15:0]<upper1;
wire ring2=initialized && !distance1[16] && distance1[15:0]>=lower2 && distance1[15:0]<upper2;
generate if(STYLE==1)begin: segmented
 assign hit=cross1 || (dash1 && (ring0 || ring1 || ring2));
 assign color=cross1?24'h315865:ring0?24'h1b5867:ring1?24'h123f4d:24'h0b2937;
end else if(STYLE==2)begin: breathing
 assign hit=ring0 || distance1<=2;
 assign color=distance1<=2?24'h183c49:breath1==0?24'h0c2e3c:breath1==1?24'h123d4c:breath1==2?24'h184d5c:24'h1e5c6c;
end else begin: double_pulse
 assign hit=ring0 || ring1 || distance1<=2;
 assign color=distance1<=2?24'h173946:ring0?24'h1e5665:24'h0b2b36;
end endgenerate
endmodule
