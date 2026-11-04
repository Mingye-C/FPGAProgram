module st7789_spi_tx #(parameter integer HALF_CYCLES=50)(
 input clk,rst,start,dc_in,last_in,input[7:0]data_in,
 output reg busy,done,sck,mosi,dc,cs_n);
localparam CW=(HALF_CYCLES<2)?1:$clog2(HALF_CYCLES);
reg[CW-1:0]div_count;reg[2:0]bit_index;reg[7:0]shift;reg finishing,last_byte;
always @(posedge clk or posedge rst)begin
 if(rst)begin busy<=0;done<=0;sck<=1;mosi<=0;dc<=1;cs_n<=1;div_count<=0;bit_index<=0;shift<=0;finishing<=0;last_byte<=1;end
 else begin done<=0;
  if(!busy)begin
   if(start)begin busy<=1;dc<=dc_in;cs_n<=0;shift<=data_in;bit_index<=7;div_count<=HALF_CYCLES-1;last_byte<=last_in;finishing<=0;end
  end else if(div_count!=0)div_count<=div_count-1'b1;
  else begin div_count<=HALF_CYCLES-1;
   if(finishing)begin busy<=0;done<=1;if(last_byte)cs_n<=1;end
   else if(sck)begin sck<=0;mosi<=shift[7];end
   else begin sck<=1;if(bit_index==0)finishing<=1;else begin bit_index<=bit_index-1'b1;shift<={shift[6:0],1'b0};end end
  end
 end
end
endmodule
