module video_frame_compositor #(parameter integer SRC_WIDTH=320, SRC_HEIGHT=200,EXTERNAL_LINE_RAM=0)(
 input[2:0]zoom_level,input clk,input rst,input start,
 input pixel_valid,input [15:0] pixel_data,output pixel_ready,input source_done,
 input write_ready,output write_en,output [31:0] write_data,
 output reg frame_done,output reg [18:0] output_count,
 output cache_write_en,output[9:0]cache_write_addr,output[23:0]cache_write_data,
 output[9:0]cache_read_addr,input[23:0]cache_read_data
);
localparam SCAN=0,R0=1,R1=2,R2=3,R3=4,CAP=5,CALC=6,EMIT=7;
localparam integer COL_BITS=$clog2(SRC_WIDTH), BANK_STRIDE=1<<COL_BITS;
reg [2:0] state;
reg zoom_latched;
wire[8:0]fw=zoom_latched?488:244,fh=zoom_latched?305:153;

wire image_row=zoom_latched?(oy>=27&&oy<332):(oy>=103&&oy<256);
wire[8:0]next_col=ox[8:0]+{8'd0,write_en};
wire[8:0]full_map_x=next_col-9'd151;
wire[8:0]half_map_x={next_col[7:0],1'b1}-9'd34;
wire[8:0]next_row=oy-{8'd0,(write_en&&ox==639&&image_row)};
wire[8:0]full_map_y=9'd331-next_row;
wire[8:0]half_map_y=9'd510-{next_row[7:0],1'b0};

(* ram_style="block" *) reg [COL_BITS+7:0] x_map[0:511];
(* ram_style="block" *) reg [15:0] y_map[0:511];
integer i,q;
initial begin
 for(i=0;i<512;i=i+1)begin x_map[i]=0;y_map[i]=0;end
 for(i=0;i<488;i=i+1)begin
  q=(((2*i+1)*SRC_WIDTH-488)*256+488)/976;
  if(q<0)q=0;if(q>(SRC_WIDTH-1)*256)q=(SRC_WIDTH-1)*256;
  x_map[i]=q;
 end
 for(i=0;i<305;i=i+1)begin
  q=(((2*i+1)*SRC_HEIGHT-305)*256+305)/610;
  if(q<0)q=0;if(q>(SRC_HEIGHT-1)*256)q=(SRC_HEIGHT-1)*256;
  y_map[i]=q;
 end
end
reg [COL_BITS+7:0] x_coord;
reg [15:0] y_coord;
reg [9:0] ox;
reg [8:0] oy;
wire [9:0] dx=ox-10'd151;
wire [8:0] dy=9'd331-oy;
wire [COL_BITS-1:0] x0=x_coord[COL_BITS+7:8];
wire [7:0] y0=y_coord[15:8];
wire [7:0] wx=x_coord[7:0],wy=y_coord[7:0];
wire [COL_BITS-1:0] x1=x0==SRC_WIDTH-1?x0:x0+1'b1;
wire [7:0] y1=y0==SRC_HEIGHT-1?y0:y0+1'b1;
reg wr_bank;
reg [1:0] line_ready;
reg [COL_BITS-1:0] capture_x;
reg [7:0] held_low_row;
reg running,emitted;
reg [1:0] phase;
reg cache_valid,reuse_column;
reg [COL_BITS-1:0] cache_x;
wire[15:0]ram_q;reg[15:0]p00,p01,p10,p11;
reg [15:0] h0r,h0g,h0b;
reg [23:0] result_rgb;
wire image_pixel=image_row&&(zoom_latched?(ox>=151&&ox<639):(ox>=273&&ox<517));
wire media_window=ox>=150 && ox<640 && oy<360;
wire [23:0] background=media_window?24'h000000:
                         24'h102642;
assign pixel_ready=running && !emitted && !line_ready[wr_bank];
wire take=pixel_valid && pixel_ready;
wire rows_ready=line_ready[y0[0]] && line_ready[y1[0]];
wire [COL_BITS:0] read_addr=(state==R0)?{y0[0],x0}:
                       (state==R1)?{y0[0],x1}:
                       (state==R2)?(reuse_column?{y0[0],x1}:{y1[0],x0}):{y1[0],x1};
assign cache_write_en=take;assign cache_write_addr={{(9-COL_BITS){1'b0}},wr_bank,capture_x};
assign cache_write_data={8'd0,pixel_data};assign cache_read_addr={{(9-COL_BITS){1'b0}},read_addr};
generate if(EXTERNAL_LINE_RAM)begin:external_cache
 assign ram_q=cache_read_data[15:0];
end else begin:private_cache
 (*ram_style="block"*)reg[15:0]lines[0:2*BANK_STRIDE-1];reg[15:0]q;
 always @(posedge clk)begin if(take)lines[{wr_bank,capture_x}]<=pixel_data;q<=lines[read_addr];end
 assign ram_q=q;
end endgenerate
assign write_en=running && !emitted && write_ready &&
                 ((state==SCAN && !image_pixel) || state==EMIT);
wire[23:0]emit_rgb=phase==3?{vertical_r[23:16],vertical_g[23:16],vertical_b[23:16]}:result_rgb;
assign write_data={(state==EMIT?emit_rgb:background),8'd0};

wire [7:0] ar=phase==0?{p00[15:11],p00[15:13]}:{p10[15:11],p10[15:13]};
wire [7:0] br=phase==0?{p01[15:11],p01[15:13]}:{p11[15:11],p11[15:13]};
reg signed [16:0] mul_r;
wire [7:0] weight_r=phase<2?wx:wy;
wire [15:0] base_r=phase<2?{ar,8'd0}:h0r;
(* use_dsp="yes" *) reg signed [25:0] product_r;
reg [15:0] baseq_r;
wire [15:0] horizontal_r=baseq_r+product_r[15:0];
wire signed [25:0] vertical_r=$signed({2'd0,baseq_r,8'd0})+product_r+26'sd32768;
always @* begin
 if(phase<2)mul_r=$signed({1'b0,br})-$signed({1'b0,ar});
 else mul_r=$signed({1'b0,horizontal_r})-$signed({1'b0,h0r});
end
always @(posedge clk)begin
 product_r<=mul_r*$signed({1'b0,weight_r});baseq_r<=base_r;
 if(running && state==CALC && phase==1)h0r<=horizontal_r;
end
wire [7:0] ag=phase==0?{p00[10:5],p00[10:9]}:{p10[10:5],p10[10:9]};
wire [7:0] bg=phase==0?{p01[10:5],p01[10:9]}:{p11[10:5],p11[10:9]};
reg signed [16:0] mul_g;
wire [7:0] weight_g=phase<2?wx:wy;
wire [15:0] base_g=phase<2?{ag,8'd0}:h0g;
(* use_dsp="yes" *) reg signed [25:0] product_g;
reg [15:0] baseq_g;
wire [15:0] horizontal_g=baseq_g+product_g[15:0];
wire signed [25:0] vertical_g=$signed({2'd0,baseq_g,8'd0})+product_g+26'sd32768;
always @* begin
 if(phase<2)mul_g=$signed({1'b0,bg})-$signed({1'b0,ag});
 else mul_g=$signed({1'b0,horizontal_g})-$signed({1'b0,h0g});
end
always @(posedge clk)begin
 product_g<=mul_g*$signed({1'b0,weight_g});baseq_g<=base_g;
 if(running && state==CALC && phase==1)h0g<=horizontal_g;
end
wire [7:0] ab=phase==0?{p00[4:0],p00[4:2]}:{p10[4:0],p10[4:2]};
wire [7:0] bb=phase==0?{p01[4:0],p01[4:2]}:{p11[4:0],p11[4:2]};
reg signed [16:0] mul_b;
wire [7:0] weight_b=phase<2?wx:wy;
wire [15:0] base_b=phase<2?{ab,8'd0}:h0b;
(* use_dsp="yes" *) reg signed [25:0] product_b;
reg [15:0] baseq_b;
wire [15:0] horizontal_b=baseq_b+product_b[15:0];
wire signed [25:0] vertical_b=$signed({2'd0,baseq_b,8'd0})+product_b+26'sd32768;
always @* begin
 if(phase<2)mul_b=$signed({1'b0,bb})-$signed({1'b0,ab});
 else mul_b=$signed({1'b0,horizontal_b})-$signed({1'b0,h0b});
end
always @(posedge clk)begin
 product_b<=mul_b*$signed({1'b0,weight_b});baseq_b<=base_b;
 if(running && state==CALC && phase==1)h0b<=horizontal_b;
end
wire[8:0]lookup_x=zoom_latched?full_map_x:half_map_x;
wire[8:0]lookup_y=zoom_latched?full_map_y:half_map_y;
always @(posedge clk)begin
 x_coord<=x_map[lookup_x];
 y_coord<=y_map[lookup_y];
 if(running)begin
  case(state)
   R1:p00<=ram_q;
   R2:if(!reuse_column)p01<=ram_q;
   R3:if(reuse_column)p01<=ram_q;else p10<=ram_q;
   CAP:p11<=ram_q;
   EMIT:if(phase==3)result_rgb<={vertical_r[23:16],vertical_g[23:16],vertical_b[23:16]};
  endcase
  if(state==SCAN && image_pixel && cache_valid && x0==cache_x+1'b1)begin
   p00<=p01;p10<=p11;
  end
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  zoom_latched<=1;
  state<=SCAN;phase<=0;wr_bank<=0;capture_x<=0;line_ready<=0;
  cache_valid<=0;reuse_column<=0;cache_x<=0;held_low_row<=0;ox<=0;oy<=479;running<=0;emitted<=0;frame_done<=0;output_count<=0;
 end else if(start)begin
  zoom_latched<=zoom_level!=0;
  state<=SCAN;phase<=0;wr_bank<=0;capture_x<=0;line_ready<=0;
  cache_valid<=0;reuse_column<=0;cache_x<=0;held_low_row<=0;ox<=0;oy<=479;running<=1;emitted<=0;frame_done<=0;output_count<=0;
 end else if(running)begin
  if(take)begin
   if(capture_x==SRC_WIDTH-1)begin line_ready[wr_bank]<=1;wr_bank<=~wr_bank;capture_x<=0;end
   else capture_x<=capture_x+1'b1;
  end
  case(state)
   SCAN:if(image_pixel && !emitted)begin

    if(y0!=held_low_row)begin if(y0>held_low_row+1)line_ready<=0;else line_ready[held_low_row[0]]<=0;held_low_row<=y0;end
    else if(rows_ready)begin
     if(cache_valid && x0==cache_x)begin phase<=0;state<=CALC;end
     else if(cache_valid && x0==cache_x+1'b1)begin reuse_column<=1;state<=R2;end
     else begin reuse_column<=0;state<=R0;end
    end
   end
   R0:state<=R1;
   R1:state<=R2;
   R2:state<=R3;
   R3:state<=CAP;
   CAP:begin phase<=0;cache_x<=x0;cache_valid<=1;state<=CALC;end
   CALC:if(phase==2)begin state<=EMIT;phase<=3;end else phase<=phase+1'b1;
   EMIT:if(write_ready)state<=SCAN;else if(phase==3)phase<=0;
  endcase
  if(write_en)begin
   output_count<=output_count+1'b1;
   if(ox==639)begin cache_valid<=0;ox<=0;if(oy==0)emitted<=1;else oy<=oy-1'b1;end
   else ox<=ox+1'b1;
  end
  if(emitted && source_done)begin frame_done<=1;running<=0;end
 end
end
endmodule
