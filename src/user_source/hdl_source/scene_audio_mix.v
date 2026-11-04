module scene_audio_mix #(parameter ECO_ENABLE=0,ECO_ANIMATION_ENABLE=0)(input clk,input rst,input [1:0] scene_mode,
 input [6:0] eco_animation_gain,input eco_mute,input in_valid,input [23:0] in_left,in_right,
 output reg out_valid,output reg [23:0] out_left,out_right);
reg [1:0] active_mode;
reg [6:0] gain;
reg [14:0] half_second;
reg [2:0] segment;
reg [15:0] phase;
wire [15:0] step=(active_mode==1 && !segment[0])?16'd1092:16'd1365;
wire [12:0] triangle_u=phase[15]?(13'd8191-phase[14:2]):phase[14:2];
wire signed [13:0] tone=$signed({1'b0,triangle_u})-14'sd4096;
wire fire_gate=segment<4;
wire overload_gate=half_second<4800;
wire fade_down=active_mode!=scene_mode || active_mode==3 || (active_mode==1 && !fire_gate) || (ECO_ENABLE && eco_mute && scene_mode==0);
wire [6:0] target_gain=(ECO_ANIMATION_ENABLE && scene_mode==0)?eco_animation_gain:7'd64;
wire signed [16:0] l=$signed({in_left[23],in_left[23:8]});
wire signed [16:0] r=$signed({in_right[23],in_right[23:8]});

(* use_dsp="yes" *) wire signed [21:0] quiet_product_l=l*5'sd13,quiet_product_r=r*5'sd13;
wire signed [16:0] quiet_l=quiet_product_l>>>6;
wire signed [16:0] quiet_r=quiet_product_r>>>6;
wire signed [16:0] beep=overload_gate?($signed({{3{tone[13]}},tone})<<<2):17'sd0;
reg signed [16:0] mix_l,mix_r;
always @* begin
 case(active_mode)
  0:begin mix_l=l;mix_r=r;end
  1:begin mix_l={{3{tone[13]}},tone};mix_r={{3{tone[13]}},tone};end
  2:begin mix_l=quiet_l+beep;mix_r=quiet_r+beep;end
  default:begin mix_l=0;mix_r=0;end
 endcase
end
reg signed [24:0] product_l,product_r;
reg valid0;reg [7:0] raw_low_l0,raw_low_r0;
function [23:0] limit_pcm;input signed [24:0] p;begin
 if(!p[24] && (|p[23:21]))limit_pcm=24'h7fff00;
 else if(p[24] && !(&p[23:21]))limit_pcm=24'h800000;
 else limit_pcm={p[21:6],8'd0};
end endfunction
wire [23:0] clipped_l=limit_pcm(product_l),clipped_r=limit_pcm(product_r);

always @(posedge clk or posedge rst)begin
 if(rst)begin
  active_mode<=0;gain<=64;half_second<=0;segment<=0;phase<=16'h4000;
  product_l<=0;product_r<=0;valid0<=0;raw_low_l0<=0;raw_low_r0<=0;
  out_valid<=0;out_left<=0;out_right<=0;
 end else begin
  valid0<=in_valid;out_valid<=valid0;
  if(in_valid)begin
   product_l<=mix_l*$signed({1'b0,gain});product_r<=mix_r*$signed({1'b0,gain});
   raw_low_l0<=active_mode==0 && gain[6]?in_left[7:0]:8'd0;
   raw_low_r0<=active_mode==0 && gain[6]?in_right[7:0]:8'd0;
   if(fade_down)begin if(gain!=0)gain<=gain-1'b1;end
   else if(gain<target_gain)gain<=gain+1'b1;
   else if(gain>target_gain)gain<=gain-1'b1;
   if(active_mode!=scene_mode && gain==0)begin
    active_mode<=scene_mode;half_second<=0;segment<=0;phase<=16'h4000;
   end else begin
    if(half_second==23999)begin
     half_second<=0;
     if(active_mode==1)segment<=segment==5?3'd0:segment+1'b1;
     else segment<=0;
    end else half_second<=half_second+1'b1;
    if(active_mode==2 && half_second==23999)phase<=16'h4000;
    else phase<=phase+step;
   end
  end
  if(valid0)begin
   out_left<={clipped_l[23:8],raw_low_l0};
   out_right<={clipped_r[23:8],raw_low_r0};
  end
 end
end
endmodule
