module fft_audio_analyzer #(
 parameter MAX_HEIGHT=70,parameter GAIN_SHIFT=1,
 parameter LOG_FLOOR_Q3=24,parameter HEIGHT_GAIN=1,
 parameter DECAY_STEP=2
)(input wire clk,input wire rst,input wire audio_valid,
 input wire [23:0] audio_left,audio_right,input wire video_vs,
 output reg [167:0] levels,
 output wire [31:0] capture_overrun_count,output wire [31:0] overflow_count,
 output reg [31:0] fft_block_count,output wire [31:0] compute_cycles
);
 wire signed [15:0] l=audio_left[23:8],r=audio_right[23:8];
 wire signed [16:0] sum=$signed({l[15],l})+$signed({r[15],r});
 wire signed [16:0] diff=$signed({l[15],l})-$signed({r[15],r});
 wire signed [15:0] mid=sum>>>1,side=diff>>>1;
 function [15:0] abs16;input signed [15:0] a;begin abs16=a[15]?(~a+16'd1):a;end endfunction

 reg use_side;reg [9:0] mix_n;reg [26:0] mid_sum,side_sum;
 wire [26:0] mid_total=mid_sum+abs16(mid),side_total=side_sum+abs16(side);
 reg mono_valid;reg signed [15:0] mono;
 always @(posedge clk) begin
  if(rst) begin use_side<=0;mix_n<=0;mid_sum<=0;side_sum<=0;mono_valid<=0;mono<=0;end
  else begin
   mono_valid<=audio_valid;
   if(audio_valid) begin
    mono<=use_side?side:mid;mix_n<=mix_n+1'b1;
    if(mix_n==1023) begin
     mid_sum<=0;side_sum<=0;
     if({mid_total,2'b0} < {2'b0,side_total}) use_side<=1;
     else if({mid_total,1'b0} > {1'b0,side_total}) use_side<=0;
    end else begin mid_sum<=mid_total;side_sum<=side_total;end
   end
  end
 end
 wire bv,done,busy;wire [9:0] bi;wire signed [15:0] re,im;
 fft1024_serial u_fft(.clk(clk),.rst(rst),.sample_valid(mono_valid),.sample(mono),
 .bin_valid(bv),.bin_index(bi),.bin_re(re),.bin_im(im),.block_done(done),.busy(busy),
 .capture_overrun_count(capture_overrun_count),.overflow_count(overflow_count),.compute_cycles(compute_cycles));

 function [4:0] band_for_bin;input [9:0] b;begin
  if(b<2) band_for_bin=0;
  else if(b<3) band_for_bin=1;
  else if(b<4) band_for_bin=2;
  else if(b<5) band_for_bin=3;
  else if(b<6) band_for_bin=4;
  else if(b<7) band_for_bin=5;
  else if(b<8) band_for_bin=6;
  else if(b<9) band_for_bin=7;
  else if(b<11) band_for_bin=8;
  else if(b<14) band_for_bin=9;
  else if(b<18) band_for_bin=10;
  else if(b<23) band_for_bin=11;
  else if(b<30) band_for_bin=12;
  else if(b<39) band_for_bin=13;
  else if(b<50) band_for_bin=14;
  else if(b<65) band_for_bin=15;
  else if(b<84) band_for_bin=16;
  else if(b<109) band_for_bin=17;
  else if(b<141) band_for_bin=18;
  else if(b<183) band_for_bin=19;
  else if(b<237) band_for_bin=20;
  else if(b<307) band_for_bin=21;
  else if(b<398) band_for_bin=22;
  else band_for_bin=23;
 end endfunction
 wire [16:0] magnitude={1'b0,abs16(re)}+{1'b0,abs16(im)};
 wire [4:0] bin_band=band_for_bin(bi);

 (* ram_style="block" *) reg [16:0] peak[0:31];
 reg [16:0] peak_q,current_peak;
 reg [4:0] current_band;
 wire positive_bin=bv && bi>0 && bi<512;
 wire band_changed=(bin_band!=current_band);
 wire [16:0] current_max=(magnitude>current_peak)?magnitude:current_peak;
 wire peak_write=positive_bin && (band_changed || bi==511);
 wire [4:0] peak_address=(bi==511)?5'd23:current_band;
 wire [16:0] peak_data=(bi==511)?current_max:current_peak;
 reg [167:0] latest,working;
 reg smoothing,clear_levels;reg [4:0] smooth_band;
 reg [2:0] compress_state;reg [4:0] compress_band;
 reg [23:0] amplified;reg [4:0] exponent;
 reg [6:0] compressed_height;
 reg[2:0]fraction_reg,fraction_next;
 integer k,exp_calc,height_calc,frac_calc;
 reg[23:0] normalized;reg[4:0] leading_zeros;

 always @* begin

  normalized=amplified;leading_zeros=0;
  if(normalized[23:8]==0)begin normalized=normalized<<16;leading_zeros=leading_zeros+16;end
  if(normalized[23:16]==0)begin normalized=normalized<<8;leading_zeros=leading_zeros+8;end
  if(normalized[23:20]==0)begin normalized=normalized<<4;leading_zeros=leading_zeros+4;end
  if(normalized[23:22]==0)begin normalized=normalized<<2;leading_zeros=leading_zeros+2;end
  if(!normalized[23])begin normalized=normalized<<1;leading_zeros=leading_zeros+1;end
  exp_calc=amplified==0?0:23-leading_zeros;
  fraction_next=normalized[22:20];
  frac_calc=fraction_reg;
  height_calc=((exponent*8+frac_calc)-LOG_FLOOR_Q3)*HEIGHT_GAIN;
  if(amplified==0 || height_calc<=0) compressed_height=0;
  else if(height_calc>MAX_HEIGHT) compressed_height=MAX_HEIGHT;
  else compressed_height=height_calc;
 end
 always @(posedge clk) begin
  peak_q<=peak[compress_band];
  if(!rst && peak_write) peak[peak_address]<=peak_data;
 end
 integer i;
 always @(posedge clk) begin
  if(rst) begin
   current_band<=0;current_peak<=0;
   latest<=0;working<=0;compress_state<=0;compress_band<=0;
   amplified<=0;exponent<=0;fraction_reg<=0;fft_block_count<=0;
  end else begin
   if(bv && bi==0) begin current_band<=0;current_peak<=0;end
   else if(positive_bin) begin
    if(band_changed) begin current_band<=bin_band;current_peak<=magnitude;end
    else current_peak<=current_max;
   end

   if(smoothing)latest<={latest[6:0],latest[167:7]};
   if(done) begin compress_state<=1;compress_band<=0;fft_block_count<=fft_block_count+1'b1;end
   else case(compress_state)
    1:compress_state<=2;
    2:begin amplified<={7'b0,peak_q}<<GAIN_SHIFT;compress_state<=3;end
    3:begin exponent<=exp_calc;fraction_reg<=fraction_next;compress_state<=4;end
    4:begin working<={compressed_height,working[167:7]};
     if(compress_band==23) compress_state<=5;
     else begin compress_band<=compress_band+1'b1;compress_state<=1;end end
    5:begin

     if(!smoothing && !frame_start)begin latest<=working;compress_state<=0;end
    end
    default:compress_state<=0;
   endcase
  end
 end
 reg vs_q,seen_audio;reg [1:0] missing_frames;
 wire frame_start=vs_q && !video_vs;

 function [6:0] smooth;input [6:0] old_h,target;begin
  if(target>=old_h) smooth=target;
  else if(old_h-target>DECAY_STEP) smooth=old_h-DECAY_STEP;
  else smooth=target;
 end endfunction
 always @(posedge clk) begin
  if(rst) begin levels<=0;vs_q<=1;seen_audio<=0;missing_frames<=0;smoothing<=0;smooth_band<=0;clear_levels<=0;end
  else begin
   vs_q<=video_vs;if(audio_valid) seen_audio<=1;
   if(frame_start) begin
    seen_audio<=audio_valid;
    if(seen_audio || audio_valid) missing_frames<=0;else if(missing_frames!=3) missing_frames<=missing_frames+1'b1;
    smoothing<=1;smooth_band<=0;
    clear_levels<=missing_frames>=1 && !seen_audio && !audio_valid;
   end else if(smoothing)begin
    levels<={smooth(levels[6:0],clear_levels?7'd0:latest[6:0]),levels[167:7]};
    if(smooth_band==23)smoothing<=0;else smooth_band<=smooth_band+1'b1;
   end
  end
 end
`ifndef SYNTHESIS
 always @(posedge clk)if(!rst && frame_start && smoothing)$fatal(1,"VS interval shorter than 24 clocks");
`endif
endmodule
