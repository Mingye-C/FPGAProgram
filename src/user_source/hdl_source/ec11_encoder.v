module ec11_encoder #(
 parameter integer RELEASE_CLICK=0,REVERSE_DIRECTION=0,CLICK_ENABLE=0,CLICK_TICKS=1200,
 parameter integer SAMPLE_DIV=6250,
 parameter integer SWITCH_SAMPLES=80
)(input clk,input rst,input a_n,input b_n,input s_n,
 output reg step_up,output reg step_down,output reg reset_brightness,
 output reg single_click,output reg double_click);
localparam DW=(SAMPLE_DIV<2)?1:$clog2(SAMPLE_DIV);
localparam SW=(SWITCH_SAMPLES<2)?1:$clog2(SWITCH_SAMPLES);
(* ASYNC_REG="TRUE" *) reg [2:0] sync0,sync1;
reg [DW-1:0] divider;
reg [1:0] candidate,ab;
reg signed [2:0] quarters;
reg armed,s_stable;
reg [SW-1:0] s_count;
wire [1:0] sample_ab=sync1[2:1];
wire sample_tick=divider==SAMPLE_DIV-1;
localparam KW=(CLICK_TICKS<2)?1:$clog2(CLICK_TICKS);
reg [1:0] click_state;
reg [KW-1:0] click_count;
wire qualified_s=(sync1[0]!=s_stable)&&(s_count==SWITCH_SAMPLES-1);
wire press_event=qualified_s && !sync1[0];
wire release_event=qualified_s && sync1[0];
always @(posedge clk or posedge rst)begin
 if(rst)begin
  sync0<=3'b111;sync1<=3'b111;divider<=0;candidate<=3;ab<=3;
  quarters<=0;armed<=0;s_stable<=1;s_count<=0;
  step_up<=0;step_down<=0;reset_brightness<=0;single_click<=0;double_click<=0;click_state<=0;click_count<=0;
 end else begin
  sync0<={a_n,b_n,s_n};sync1<=sync0;
  step_up<=0;step_down<=0;reset_brightness<=0;single_click<=0;double_click<=0;
  if(sample_tick)begin
   divider<=0;
   candidate<=sample_ab;
   if(RELEASE_CLICK)begin if(release_event)single_click<=1;end
   else if(CLICK_ENABLE)begin

    case(click_state)
     0:begin click_count<=0;if(press_event)click_state<=1;end
     1:if(release_event)begin click_state<=2;click_count<=0;end
     2:if(press_event)begin double_click<=1;click_state<=3;click_count<=0;end
       else if(click_count==CLICK_TICKS-1)begin single_click<=1;click_state<=0;click_count<=0;end
       else click_count<=click_count+1'b1;
     3:if(release_event)click_state<=0;
    endcase
   end

   if(sample_ab==candidate)begin
    ab<=sample_ab;
    if(!armed)begin
     quarters<=0;if(sample_ab==2'b11)armed<=1;
    end else if(sample_ab!=ab)begin
     case({ab,sample_ab})
      4'b1110,4'b1000,4'b0001,4'b0111:begin
       if(sample_ab==3)begin
        if(quarters==3)begin if(REVERSE_DIRECTION)step_down<=1;else step_up<=1;end
        quarters<=0;
       end else quarters<=quarters+3'sd1;
      end
      4'b1101,4'b0100,4'b0010,4'b1011:begin
       if(sample_ab==3)begin
        if(quarters==-3'sd3)begin if(REVERSE_DIRECTION)step_up<=1;else step_down<=1;end
        quarters<=0;
       end else quarters<=quarters-3'sd1;
      end
      default:begin quarters<=0;armed<=sample_ab==3;end
     endcase
    end
   end
   if(sync1[0]==s_stable)s_count<=0;
   else if(s_count==SWITCH_SAMPLES-1)begin
    s_stable<=sync1[0];s_count<=0;
    if(!RELEASE_CLICK && !CLICK_ENABLE && !sync1[0])reset_brightness<=1;
   end else s_count<=s_count+1'b1;
  end else divider<=divider+1'b1;
 end
end
endmodule
