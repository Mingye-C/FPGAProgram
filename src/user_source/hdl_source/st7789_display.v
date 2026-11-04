module st7789_display #(
 parameter integer CLK_HZ=50_000_000,HALF_CYCLES=10,
 parameter integer HOLD_TICKS=500,
 parameter integer RESET_CYCLES=CLK_HZ/10,
 parameter integer RESET_WAIT_CYCLES=(CLK_HZ/1000)*100,
 parameter integer SLEEP_WAIT_CYCLES=(CLK_HZ/1000)*120
)(input clk,input rst,input sample_tick,output lcd_sck,output lcd_mosi,output lcd_dc,
 output wire lcd_cs_n,output reg lcd_bl,output reg lcd_rst_n,output reg done,output reg error);
`include "st7789_logo_params.vh"
localparam OLD_MAX_WAIT=(SLEEP_WAIT_CYCLES>RESET_WAIT_CYCLES)?SLEEP_WAIT_CYCLES:RESET_WAIT_CYCLES;
localparam MAX_WAIT=OLD_MAX_WAIT;
localparam TIMER_BITS=(MAX_WAIT<2)?1:$clog2(MAX_WAIT+1);
localparam RESET=0,RESET_WAIT=1,SLEEP_SEND=2,SLEEP_ACK=3,SLEEP_WAIT=4,
 CFG_SEND=5,CFG_ACK=6,ROM_ADDR=7,ROM_WAIT=8,ROM_LOAD=9,
 HIGH_SEND=10,HIGH_ACK=11,LOW_SEND=12,LOW_ACK=13,
 FINISH=14,FAULT=15,CFG_WAIT=16,LOADING_HOLD=17;
reg[4:0]state;reg[6:0]cfg_index;reg[TIMER_BITS-1:0]timer;
reg tx_start,tx_dc,tx_last;reg[7:0]tx_data;wire tx_busy,tx_done;
reg[7:0]x;reg[8:0]y;
reg loading;
reg[12:0]rom_address;wire[7:0]rom_q;
reg[1:0]rom_lane;reg[7:0]run_left;reg[15:0]color;
wire last_pixel=(x==239 && y==319);
st7789_spi_tx #(.HALF_CYCLES(HALF_CYCLES))u_spi(
 .clk(clk),.rst(rst),.start(tx_start),.dc_in(tx_dc),.data_in(tx_data),.last_in(tx_last),.cs_n(lcd_cs_n),
 .busy(tx_busy),.done(tx_done),.sck(lcd_sck),.mosi(lcd_mosi),.dc(lcd_dc));
st7789_logo_rom u_logo(.clk(clk),.address(rom_address),.q(rom_q));
wire[15:0]pixel_color=color;

(* rom_style="block" *) reg[9:0]config_rom[0:127];
reg[9:0]configuration;
initial begin
 config_rom[0]=10'h2b1;
 config_rom[1]=10'h305;
 config_rom[2]=10'h33c;
 config_rom[3]=10'h33c;
 config_rom[4]=10'h2b2;
 config_rom[5]=10'h305;
 config_rom[6]=10'h33c;
 config_rom[7]=10'h33c;
 config_rom[8]=10'h2b3;
 config_rom[9]=10'h305;
 config_rom[10]=10'h33c;
 config_rom[11]=10'h33c;
 config_rom[12]=10'h305;
 config_rom[13]=10'h33c;
 config_rom[14]=10'h33c;
 config_rom[15]=10'h2b4;
 config_rom[16]=10'h303;
 config_rom[17]=10'h2c0;
 config_rom[18]=10'h328;
 config_rom[19]=10'h308;
 config_rom[20]=10'h304;
 config_rom[21]=10'h2c1;
 config_rom[22]=10'h3c0;
 config_rom[23]=10'h2c2;
 config_rom[24]=10'h30d;
 config_rom[25]=10'h300;
 config_rom[26]=10'h2c3;
 config_rom[27]=10'h38d;
 config_rom[28]=10'h32a;
 config_rom[29]=10'h2c4;
 config_rom[30]=10'h38d;
 config_rom[31]=10'h3ee;
 config_rom[32]=10'h2c5;
 config_rom[33]=10'h31a;
 config_rom[34]=10'h236;
 config_rom[35]=10'h300;
 config_rom[36]=10'h2e0;
 config_rom[37]=10'h304;
 config_rom[38]=10'h322;
 config_rom[39]=10'h307;
 config_rom[40]=10'h30a;
 config_rom[41]=10'h32e;
 config_rom[42]=10'h330;
 config_rom[43]=10'h325;
 config_rom[44]=10'h32a;
 config_rom[45]=10'h328;
 config_rom[46]=10'h326;
 config_rom[47]=10'h32e;
 config_rom[48]=10'h33a;
 config_rom[49]=10'h300;
 config_rom[50]=10'h301;
 config_rom[51]=10'h303;
 config_rom[52]=10'h313;
 config_rom[53]=10'h2e1;
 config_rom[54]=10'h304;
 config_rom[55]=10'h316;
 config_rom[56]=10'h306;
 config_rom[57]=10'h30d;
 config_rom[58]=10'h32d;
 config_rom[59]=10'h326;
 config_rom[60]=10'h323;
 config_rom[61]=10'h327;
 config_rom[62]=10'h327;
 config_rom[63]=10'h325;
 config_rom[64]=10'h32d;
 config_rom[65]=10'h33b;
 config_rom[66]=10'h300;
 config_rom[67]=10'h301;
 config_rom[68]=10'h304;
 config_rom[69]=10'h313;
 config_rom[70]=10'h23a;
 config_rom[71]=10'h355;
 config_rom[72]=10'h221;
 config_rom[73]=10'h229;
 config_rom[74]=10'h22a;
 config_rom[75]=10'h100;
 config_rom[76]=10'h300;
 config_rom[77]=10'h100;
 config_rom[78]=10'h3ef;
 config_rom[79]=10'h22b;
 config_rom[80]=10'h100;
 config_rom[81]=10'h300;
 config_rom[82]=10'h101;
 config_rom[83]=10'h33f;
 config_rom[84]=10'h22c;
 config_rom[85]=10'h22c;
 config_rom[86]=10'h22c;
 config_rom[87]=10'h22c;
 config_rom[88]=10'h22c;
 config_rom[89]=10'h22c;
 config_rom[90]=10'h22c;
 config_rom[91]=10'h22c;
 config_rom[92]=10'h22c;
 config_rom[93]=10'h22c;
 config_rom[94]=10'h22c;
 config_rom[95]=10'h22c;
 config_rom[96]=10'h22c;
 config_rom[97]=10'h22c;
 config_rom[98]=10'h22c;
 config_rom[99]=10'h22c;
 config_rom[100]=10'h22c;
 config_rom[101]=10'h22c;
 config_rom[102]=10'h22c;
 config_rom[103]=10'h22c;
 config_rom[104]=10'h22c;
 config_rom[105]=10'h22c;
 config_rom[106]=10'h22c;
 config_rom[107]=10'h22c;
 config_rom[108]=10'h22c;
 config_rom[109]=10'h22c;
 config_rom[110]=10'h22c;
 config_rom[111]=10'h22c;
 config_rom[112]=10'h22c;
 config_rom[113]=10'h22c;
 config_rom[114]=10'h22c;
 config_rom[115]=10'h22c;
 config_rom[116]=10'h22c;
 config_rom[117]=10'h22c;
 config_rom[118]=10'h22c;
 config_rom[119]=10'h22c;
 config_rom[120]=10'h22c;
 config_rom[121]=10'h22c;
 config_rom[122]=10'h22c;
 config_rom[123]=10'h22c;
 config_rom[124]=10'h22c;
 config_rom[125]=10'h22c;
 config_rom[126]=10'h22c;
 config_rom[127]=10'h22c;
end
always @(posedge clk)configuration<=config_rom[cfg_index];
always @(posedge clk or posedge rst)begin
 if(rst)begin
  loading<=1;state<=RESET;timer<=RESET_CYCLES-1;lcd_rst_n<=0;lcd_bl<=0;done<=0;error<=0;
  tx_start<=0;tx_last<=1;tx_dc<=0;tx_data<=0;cfg_index<=0;
  x<=0;y<=0;rom_address<=0;rom_lane<=0;run_left<=0;color<=0;
 end else begin
  tx_start<=0;

  timer<=timer-1'b1;
  case(state)
   RESET:if(timer==0) begin lcd_rst_n<=1;timer<=RESET_WAIT_CYCLES-1;state<=RESET_WAIT;end
   RESET_WAIT:if(timer==0) state<=SLEEP_SEND;
   SLEEP_SEND:if(!tx_busy)begin tx_data<=8'h11;tx_dc<=0;tx_start<=1;state<=SLEEP_ACK;end
   SLEEP_ACK:if(tx_done)begin timer<=SLEEP_WAIT_CYCLES-1;state<=SLEEP_WAIT;end
   SLEEP_WAIT:if(timer==0) begin cfg_index<=0;state<=CFG_SEND;end
   CFG_SEND:if(!tx_busy)begin tx_last<=configuration[9];tx_data<=configuration[7:0];tx_dc<=configuration[8];tx_start<=1;state<=CFG_ACK;end
   CFG_ACK:if(tx_done)begin
    if(cfg_index==84)begin
     x<=0;y<=0;rom_address<=loading?13'd0:LOADING_DATA_BYTES;rom_lane<=0;
     state<=ROM_ADDR;
    end else begin cfg_index<=cfg_index+1'b1;state<=CFG_WAIT;end
   end
   CFG_WAIT:state<=CFG_SEND;
   ROM_ADDR:if(rom_address>=LOGO_DATA_BYTES)begin error<=1;state<=FAULT;end else state<=ROM_WAIT;
   ROM_WAIT:state<=ROM_LOAD;
   ROM_LOAD:begin
    rom_address<=rom_address+1'b1;
    case(rom_lane)
     0:begin run_left<=rom_q;rom_lane<=1;state<=ROM_ADDR;end
     1:begin color[15:8]<=rom_q;rom_lane<=2;state<=ROM_ADDR;end
     default:begin color[7:0]<=rom_q;rom_lane<=0;state<=HIGH_SEND;end
    endcase
   end
   HIGH_SEND:if(!tx_busy)begin tx_last<=0;tx_dc<=1;tx_data<=pixel_color[15:8];tx_start<=1;state<=HIGH_ACK;end
   HIGH_ACK:if(tx_done)state<=LOW_SEND;
   LOW_SEND:if(!tx_busy)begin tx_last<=1;tx_dc<=1;tx_data<=pixel_color[7:0];tx_start<=1;state<=LOW_ACK;end
   LOW_ACK:if(tx_done)begin
    if(last_pixel)begin
     if(run_left!=0 || rom_address!=(loading?LOADING_DATA_BYTES:LOGO_DATA_BYTES))begin error<=1;state<=FAULT;end

     else if(loading)begin lcd_bl<=1;rom_address<=0;state<=LOADING_HOLD;end
     else begin done<=1;state<=FINISH;end
    end else begin
     if(x==239)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
     if(run_left!=0)begin run_left<=run_left-1'b1;state<=HIGH_SEND;end
     else state<=ROM_ADDR;
    end
   end
   LOADING_HOLD:if(sample_tick)begin if(rom_address==HOLD_TICKS)begin loading<=0;cfg_index<=74;state<=CFG_WAIT;end else rom_address<=rom_address+1'b1;end
   FINISH:begin end
   FAULT:begin error<=1;end
   default:begin error<=1;state<=FAULT;end
  endcase
 end
end
endmodule
