module dht11_reader #(
 parameter integer CLOCKS_PER_US=50, BOOT_TICKS=801, PERIOD_TICKS=1601,
 parameter integer START_TICKS=16, FAIL_LIMIT=5
)(input clk,rst,slow_tick,input data_in,input status_ack,output drive_low,
 output reg [15:0] bcd,output reg valid,output reg update_toggle,
 (*preserve="true",keep="true"*)output reg [2:0] status,output reg [2:0] failures);
 localparam BOOT=0,START=1,RELEASE=2,RESPONSE_LOW=3,RESPONSE_HIGH=4,
 BIT_LOW=5,BIT_HIGH=6,CONVERT_H=7,CONVERT_T=8,WAIT_NEXT=9,FAIL=10;
 reg[3:0]state;
 (* async_reg="true",preserve="true" *)reg[1:0]data_sync;
 (*async_reg="true",preserve="true",keep="true"*)reg[1:0]ack_sync;
 reg[$clog2(CLOCKS_PER_US)-1:0]us_div;
 wire us_tick=us_div==CLOCKS_PER_US-1;
 reg[10:0]timer;
 reg[5:0]bit_no;
 reg[7:0]shift,sum;
 reg[6:0]humidity,temperature;
 assign drive_low=state==START;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   data_sync<=3;ack_sync<=0;us_div<=0;state<=BOOT;timer<=0;bit_no<=0;shift<=0;sum<=0;
   humidity<=0;temperature<=0;bcd<=0;valid<=0;update_toggle<=0;status<=0;failures<=0;
  end else begin
   data_sync<={data_sync[0],data_in};ack_sync<={ack_sync[0],status_ack};
   if(us_tick)us_div<=0;else us_div<=us_div+1'b1;
   case(state)
    BOOT,WAIT_NEXT:if(slow_tick)begin
     if(timer==(state==BOOT?BOOT_TICKS-1:PERIOD_TICKS-1))begin

      if(state==BOOT || ack_sync[1]==update_toggle)begin
       state<=START;timer<=0;bit_no<=0;sum<=0;shift<=0;
      end
     end else timer<=timer+1'b1;
    end
    START:if(slow_tick)begin
     if(timer==START_TICKS-1)begin state<=RELEASE;timer<=0;end
     else timer<=timer+1'b1;
    end

    RELEASE:if(us_tick)begin
     if(data_sync[1])begin state<=RESPONSE_LOW;timer<=0;end
     else if(timer==120)begin state<=FAIL;status<=2;end
     else timer<=timer+1'b1;
    end
    RESPONSE_LOW:if(us_tick)begin
     if(!data_sync[1])begin state<=RESPONSE_HIGH;timer<=0;end
     else if(timer==120)begin state<=FAIL;status<=2;end
     else timer<=timer+1'b1;
    end
    RESPONSE_HIGH:if(us_tick)begin
     if(data_sync[1])begin
      if(timer<40)begin state<=FAIL;status<=4;end
      else begin state<=BIT_LOW;timer<=0;end
     end
     else if(timer==120)begin state<=FAIL;status<=2;end
     else timer<=timer+1'b1;
    end

    BIT_LOW:if(us_tick)begin
     if(!data_sync[1])begin
      if(timer<40)begin state<=FAIL;status<=4;end
      else begin state<=BIT_HIGH;timer<=0;end
     end
     else if(timer==120)begin state<=FAIL;status<=2;end
     else timer<=timer+1'b1;
    end
    BIT_HIGH:if(us_tick)begin

     if(!timer[10])begin
      if(data_sync[1])begin
       if(timer[6:0]<20)begin state<=FAIL;status<=4;end
       else timer<=11'd1024;
      end
      else if(timer[6:0]==120)begin state<=FAIL;status<=2;end
      else timer<=timer+1'b1;
     end else if(!data_sync[1] && timer[6:0]<15)begin state<=FAIL;status<=4;end
     else if(!data_sync[1])begin
      shift<={shift[6:0],timer[6:0]>=50};timer<=0;
      if(bit_no[2:0]==7)begin
       if(bit_no==39)begin
        if({shift[6:0],timer[6:0]>=50}!=sum)begin state<=FAIL;status<=3;end
        else if(humidity>99 || temperature>99)begin state<=FAIL;status<=4;end
        else begin state<=CONVERT_H;shift<={1'b0,humidity};bit_no<=0;end
       end else begin
        sum<=sum+{shift[6:0],timer[6:0]>=50};
        if(bit_no==7)humidity<={shift[5:0],timer[6:0]>=50};
        if(bit_no==23)temperature<={shift[5:0],timer[6:0]>=50};
        if((bit_no==7 || bit_no==23)&&shift[6])begin state<=FAIL;status<=4;end
        else begin state<=BIT_HIGH;bit_no<=bit_no+1'b1;end
       end
      end else begin state<=BIT_HIGH;bit_no<=bit_no+1'b1;end
     end else if(timer[6:0]==120)begin state<=FAIL;status<=2;end
     else timer<=timer+1'b1;
    end

    CONVERT_H,CONVERT_T:begin
     if(shift>=10)begin shift<=shift-8'd10;bit_no<=bit_no+1'b1;end
     else if(state==CONVERT_H)begin
      bcd[7:0]<={bit_no[3:0],shift[3:0]};shift<={1'b0,temperature};bit_no<=0;state<=CONVERT_T;
     end else begin
      bcd[15:8]<={bit_no[3:0],shift[3:0]};valid<=1;failures<=0;status<=1;
      update_toggle<=~update_toggle;timer<=0;state<=WAIT_NEXT;
     end
    end
    FAIL:begin
     if(failures<FAIL_LIMIT)failures<=failures+1'b1;
     if(failures==FAIL_LIMIT-1 && valid)begin valid<=0;update_toggle<=~update_toggle;end
     timer<=0;state<=WAIT_NEXT;
    end
    default:begin state<=BOOT;timer<=0;valid<=0;end
   endcase
  end
 end
endmodule
