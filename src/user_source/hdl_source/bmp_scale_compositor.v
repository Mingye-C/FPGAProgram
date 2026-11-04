module bmp_scale_compositor #(parameter EXTERNAL_LINE_RAM=0)(
 input[2:0]zoom_level,input clk,input rst,input start,input abort,input streaming,input source_done,
 input [12:0] src_width,input [12:0] src_height,input dimensions_valid,
 input in_valid,input [23:0] in_rgb,output in_ready,output sector_ready,input write_ready,
 output write_en,output [31:0] write_data,output frame_done,output reg failed,
 output reg [18:0] output_count,output reg [8:0] fit_width,output reg [8:0] fit_height,
 output configured,output cache_write_en,output [9:0] cache_write_addr,
 output [23:0] cache_write_data,output [9:0] cache_read_addr,input [23:0] cache_read_data);
 reg zoom_latched;
 reg active,running,exhausted,emitted,rows_done;reg [3:0]prep;
 reg [12:0]sw,sh,sx,sy;reg[12:0]last_source_x;
 reg [9:0]ox,x0;reg [8:0]oy,y0,dx;
 reg signed [21:0]xq,yq;
 reg [20:0]x_step,y_step;reg[9:0]xr,yr,x_step_rem,y_step_rem;
 wire signed[21:0]x_initial=$signed({2'd0,x_step[20:1]})-22'sd128;
 wire[9:0]initial_rem_sum=x_step_rem+(x_step[0]?{1'b0,fit_width}:10'd0);
 wire[9:0]x_initial_rem={1'b0,initial_rem_sum[9:1]};
 reg width_limited,div_start;reg[23:0]div_num;reg[12:0]div_den;
 wire div_done;wire[23:0]quotient;wire[12:0]remainder;
 bmp_fit_divider ratio(.clk(clk),.rst(rst||start||abort),.start(div_start),.numerator(div_num),.denominator(div_den),.done(div_done),.quotient(quotient),.remainder(remainder));
wire[8:0]scale_operand=quotient==0?9'd1:width_limited?(quotient>360?9'd360:quotient[8:0]):(quotient>490?9'd490:quotient[8:0]);
 wire[8:0]scale_result=scaled_fit(scale_operand,zoom_latched);
 function[8:0]scaled_fit;input[8:0]n;input[2:0]z;reg[11:0]v;begin
 v={3'd0,n}+1;scaled_fit=z==0?(v[9:1]==0?9'd1:v[9:1]):n;end endfunction
 assign configured=prep==11;
 wire[12:0]px0=xq<0 ? 13'd0:xq[20:8]>=last_source_x ? last_source_x:xq[20:8];
 wire[12:0]px1=px0==last_source_x ? px0:px0+1'b1;
 wire[7:0]xf=xq<0||px0==last_source_x ? 8'd0:xq[7:0];
 wire[12:0]mapped_y=yq<0 ? 13'd0:yq[20:8]>=sh-1'b1 ? sh-1'b1:yq[20:8];
 reg[12:0]py0,py1;reg[7:0]yf;
 reg[1:0]valid_rows;reg[12:0]row0,row1;
 wire have0=valid_rows[py0[0]]&&(py0[0] ? row1:row0)==py0;
 wire have1=valid_rows[py1[0]]&&(py1[0] ? row1:row0)==py1;
 wire selected_row=!rows_done&&(sy==py0||sy==py1)&&!(valid_rows[sy[0]]&&(sy[0] ? row1:row0)==sy);
 reg[2:0]hs;reg[3:0]vs;reg[1:0]hc,vc;reg xcarry_saved;
 reg[23:0]previous,left_rgb,right_rgb,h_rgb,lo_rgb,hi_rgb,v_rgb;
 reg[7:0]hfrac;reg hbank;reg[12:0]pair_x;
 wire[9:0]xrs=xr+x_step_rem,yrs=yr+y_step_rem;
 wire xcarry=xrs>={1'b0,fit_width},ycarry=yrs>={1'b0,fit_height};

 wire signed[21:0]next_xq=xq;
 wire[12:0]next_px0=next_xq<0 ? 13'd0:next_xq[20:8]>=last_source_x ? last_source_x:next_xq[20:8];
 wire[12:0]next_px1=next_px0==last_source_x ? next_px0:next_px0+1'b1;
 assign in_ready=active&&configured&&!failed&&!exhausted&&hs==0&&vs!=8&&vs!=9&&(rows_done||sy<=py1);
 wire accept=in_valid&&in_ready;
 assign sector_ready=active&&configured&&!failed;
 wire image_row=oy>=y0&&oy<y0+fit_height;
 wire image_pixel=image_row&&ox>=x0&&ox<x0+fit_width;
 wire[8:0]local_x=ox-x0;
 reg read_bank;
 assign cache_read_addr={read_bank,local_x};
 assign cache_write_en=hs==3&&!rst&&!start&&!abort&&!failed;
 assign cache_write_addr={hbank,dx};assign cache_write_data=h_rgb;
 wire[23:0]row_pixel;
 generate if(EXTERNAL_LINE_RAM)begin:external_cache
  assign row_pixel=cache_read_data;
 end else begin:private_cache
  (*ram_style="block"*)reg[23:0]lines[0:1023];reg[23:0]q;
  always @(posedge clk)begin if(cache_write_en)lines[cache_write_addr]<=cache_write_data;q<=lines[cache_read_addr];end
  assign row_pixel=q;
 end endgenerate
 function[7:0]channel;input[23:0]rgb;input[1:0]c;begin case(c)0:channel=rgb[23:16];1:channel=rgb[15:8];default:channel=rgb[7:0];endcase end endfunction
 wire vertical_calc=vs==5||vs==6;
 wire[7:0]mix_a=vertical_calc ? channel(lo_rgb,vc):channel(left_rgb,hc);
 wire[7:0]mix_b=vertical_calc ? channel(hi_rgb,vc):channel(right_rgb,hc);
 wire[7:0]mix_f=vertical_calc ? yf:hfrac;
 wire signed[8:0]delta=$signed({1'b0,mix_b})-$signed({1'b0,mix_a});
 (*use_dsp="yes"*)reg signed[17:0]product;
 wire signed[17:0]sum=$signed({2'b0,mix_a,8'd0})+product+18'sd128;
 wire[7:0]mixed=sum[15:8];
 wire media_window=ox>=150&&oy<360;
 assign write_en=active&&running&&vs==7&&write_ready&&!failed&&!abort;
 assign write_data={image_pixel ? v_rgb:media_window ? 24'h000000:24'h102642,8'd0};
 assign frame_done=emitted&&source_done&&exhausted&&!failed;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   zoom_latched<=1;active<=0;running<=0;exhausted<=0;emitted<=0;rows_done<=0;failed<=0;output_count<=0;
   prep<=0;last_source_x<=0;sw<=0;sh<=0;sx<=0;sy<=0;ox<=0;oy<=479;x0<=150;y0<=0;dx<=0;
   fit_width<=0;fit_height<=0;xq<=0;yq<=0;x_step<=0;y_step<=0;
   xr<=0;yr<=0;x_step_rem<=0;y_step_rem<=0;
   width_limited<=0;div_start<=0;div_num<=0;div_den<=1;valid_rows<=0;row0<=0;row1<=0;
   hs<=0;vs<=0;hc<=0;vc<=0;previous<=0;left_rgb<=0;right_rgb<=0;h_rgb<=0;lo_rgb<=0;hi_rgb<=0;v_rgb<=0;
   hfrac<=0;hbank<=0;pair_x<=0;read_bank<=0;product<=0;xcarry_saved<=0;py0<=0;py1<=0;yf<=0;
  end else if(start)begin
   zoom_latched<=zoom_level[0];
   active<=1;running<=0;exhausted<=0;emitted<=0;rows_done<=0;failed<=0;output_count<=0;
   prep<=0;sx<=0;sy<=0;ox<=0;oy<=479;dx<=0;valid_rows<=0;hs<=0;vs<=0;div_start<=0;previous<=0;
  end else if(abort)begin active<=0;running<=0;hs<=0;vs<=0;div_start<=0;valid_rows<=0;end
  else if(active&&!failed)begin
   div_start<=0;
   case(prep)
    0:if(dimensions_valid)begin sw<=src_width;sh<=src_height;prep<=1;end
    1:begin
     last_source_x<=sw-1'b1;
     if(sw==0||sh==0||sw>4096||sh>4096)failed<=1;
     width_limited<=sw*24'd360>=sh*24'd490;
     if(sw*24'd360>=sh*24'd490)begin fit_width<=zoom_latched?490:245;div_num<=sh*24'd490+(sw>>1);div_den<=sw;end
     else begin fit_height<=zoom_latched?360:180;div_num<=sw*24'd360+(sh>>1);div_den<=sh;end
     div_start<=1;prep<=2;
    end
    2:if(div_done)begin
     if(width_limited)fit_height<=scale_result;
     else fit_width<=scale_result;prep<=3;
    end
    3:begin div_num<={3'd0,sw,8'd0};div_den<={4'd0,fit_width};div_start<=1;prep<=4;
     x0<=150+((490-fit_width)>>1);y0<=(360-fit_height)>>1;end
    4:if(div_done)begin x_step<=quotient[20:0];x_step_rem<=remainder[9:0];div_num<={3'd0,sh,8'd0};div_den<={4'd0,fit_height};div_start<=1;prep<=5;end
    5:if(div_done)begin y_step<=quotient[20:0];y_step_rem<=remainder[9:0];div_num<={4'd0,sw,7'd0};div_den<={4'd0,fit_width};div_start<=1;prep<=6;end
    6:if(div_done)begin xq<=$signed({1'b0,quotient[20:0]})-22'sd128;xr<=remainder[9:0];div_num<={4'd0,sh,7'd0};div_den<={4'd0,fit_height};div_start<=1;prep<=7;end
    7:if(div_done)begin yq<=$signed({1'b0,quotient[20:0]})-22'sd128;yr<=remainder[9:0];prep<=8;end
    8:begin py0<=mapped_y;yf<=yq<0||mapped_y==sh-1'b1 ? 0:yq[7:0];prep<=9;end
    9:begin py1<=py0==sh-1'b1 ? py0:py0+1'b1;prep<=11;end
   endcase
   if(streaming&&write_ready&&configured&&!emitted)running<=1;
   if(accept)begin
    previous<=in_rgb;
    if(sx==last_source_x)begin sx<=0;if(sy==sh-1'b1)exhausted<=1;else sy<=sy+1'b1;end
    else sx<=sx+1'b1;
    if(selected_row&&sx==px1)begin
     if(dx==0)begin valid_rows[sy[0]]<=0;if(sy[0])row1<=sy;else row0<=sy;end
     left_rgb<=px0==px1 ? in_rgb:previous;right_rgb<=in_rgb;hfrac<=xf;hbank<=sy[0];pair_x<=sx;hc<=0;hs<=1;
    end
   end

   if(hs==1&&!vertical_calc&&vs!=4)begin
    product<=delta*$signed({1'b0,mix_f});hs<=2;
    if(hc==0)begin xq<=xq+$signed({1'b0,x_step});xr<=xcarry ? xrs-fit_width:xrs;xcarry_saved<=xcarry;end
   end
   if(hs==2&&!vertical_calc)begin
    if(hc==0)xq<=xq+xcarry_saved;
    case(hc)0:h_rgb[23:16]<=mixed;1:h_rgb[15:8]<=mixed;2:h_rgb[7:0]<=mixed;endcase
    if(hc==2)hs<=3;else begin hc<=hc+1'b1;hs<=1;end
   end
   if(hs==3)begin
    hs<=0;
    if(dx==fit_width-1'b1)begin
     valid_rows[hbank]<=1;
     dx<=0;xq<=x_initial;xr<=x_initial_rem;
    end else begin
     dx<=dx+1'b1;
     if(next_px1==pair_x)begin
      hfrac<=next_xq<0||next_px0==last_source_x ? 0:next_xq[7:0];
      if(next_px0==last_source_x)left_rgb<=right_rgb;
      hc<=0;hs<=1;
     end
    end
   end
   if(running)case(vs)
    0:if(!image_pixel)begin v_rgb<=0;vs<=7;end
      else if(have0&&have1)begin read_bank<=py0[0];vs<=1;end
    1:vs<=2;
    2:begin lo_rgb<=row_pixel;read_bank<=py1[0];vs<=3;end
    3:vs<=4;
    4:if(hs!=2)begin hi_rgb<=row_pixel;vc<=0;vs<=5;end
    5:begin product<=delta*$signed({1'b0,mix_f});vs<=6;end
    6:begin
     case(vc)0:v_rgb[23:16]<=mixed;1:v_rgb[15:8]<=mixed;2:v_rgb[7:0]<=mixed;endcase
     if(vc==2)vs<=7;else begin vc<=vc+1'b1;vs<=5;end
    end
    7:if(write_ready)begin
     output_count<=output_count+1'b1;vs<=0;
     if(ox==639)begin
      ox<=0;
      if(image_row)begin
       yq<=yq+$signed({1'b0,y_step})+ycarry;yr<=ycarry ? yrs-fit_height:yrs;
       if(oy==y0)rows_done<=1;else vs<=8;
      end
      if(oy==0)begin emitted<=1;running<=0;end else oy<=oy-1'b1;
     end else ox<=ox+1'b1;
    end
    8:begin py0<=mapped_y;yf<=yq<0||mapped_y==sh-1'b1 ? 0:yq[7:0];vs<=9;end
    9:begin py1<=py0==sh-1'b1 ? py0:py0+1'b1;vs<=0;end
   endcase
   if(source_done&&!exhausted)failed<=1;
  end
 end

endmodule

module bmp_fit_divider(input clk,input rst,input start,input [23:0] numerator,
 input [12:0] denominator,output reg done,output reg [23:0] quotient,output reg [12:0] remainder);
reg busy;reg [4:0] count;reg [23:0] work;reg [12:0] divisor;reg [13:0] rem_work;
wire [13:0] trial={rem_work[12:0],work[23]};
wire subtract=trial>={1'b0,divisor};
wire [13:0] reduced=subtract?trial-{1'b0,divisor}:trial;
always @(posedge clk or posedge rst)begin
 if(rst)begin busy<=0;done<=0;count<=0;work<=0;divisor<=1;rem_work<=0;quotient<=0;remainder<=0;end
 else begin
  done<=0;
  if(start)begin busy<=1;count<=0;work<=numerator;divisor<=denominator;rem_work<=0;end
  else if(busy)begin
   work<={work[22:0],subtract};rem_work<=reduced;
   if(count==23)begin busy<=0;done<=1;quotient<={work[22:0],subtract};remainder<=reduced[12:0];end
   else count<=count+1'b1;
  end
 end
end
endmodule
