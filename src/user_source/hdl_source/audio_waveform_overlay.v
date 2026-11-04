module audio_waveform_overlay #(
    parameter HISTORY_RAM=0,ECO_ENABLE=0,
    parameter integer PANEL_X=448,
    parameter integer PANEL_Y=16,
    parameter integer PANEL_WIDTH=180,
    parameter integer PANEL_HEIGHT=90,
    parameter integer BAR_COUNT=45,
    parameter integer BAR_PITCH=PANEL_WIDTH/BAR_COUNT,
    parameter integer BAR_WIDTH=2,
    parameter integer MAX_HALF_HEIGHT=40,
    parameter integer WINDOW_LOG2=10,
    parameter USE_PEAK=1'b0,
    parameter integer GAIN_SHIFT=3,
    parameter integer AMPLITUDE_SHIFT=10,
    parameter integer NORMALIZE_SHIFT=8,
    parameter integer ATTACK_SHIFT=1,
    parameter integer RELEASE_SHIFT=3,
    parameter integer UPDATE_FRAMES=2,
    parameter [23:0] COLOR_0=24'ha438c5,
    parameter [23:0] COLOR_1=24'hb33cc9,
    parameter [23:0] COLOR_2=24'hc240cb,
    parameter [23:0] COLOR_3=24'hd247cd,
    parameter [23:0] COLOR_4=24'he350cc,
    parameter [23:0] COLOR_5=24'hf05fc7,
    parameter [23:0] COLOR_6=24'hfa70c1,
    parameter [23:0] COLOR_7=24'hff83bf
)(
    input clk,input rst,input eco_active,
    input audio_valid,input [23:0] audio_left,input [23:0] audio_right,
    input [23:0] in_rgb,input in_de,input in_hs,input in_vs,
    output reg [23:0] out_rgb,
    output reg out_de,output reg out_hs,output reg out_vs
);
localparam integer CENTER=PANEL_HEIGHT/2;
localparam integer LEFT_PAD=(PANEL_WIDTH-BAR_COUNT*BAR_PITCH)/2;
localparam [15:0] ENVELOPE_LIMIT=MAX_HALF_HEIGHT<<AMPLITUDE_SHIFT;
reg de_prev,vs_prev,sample_seen;
reg [10:0] x_count,y_count;
wire frame_tick=vs_prev && !in_vs;
wire silent_frame=frame_tick && !sample_seen && !audio_valid;

wire [15:0] pcm_l=audio_left[23:8],pcm_r=audio_right[23:8];
wire [15:0] abs_l=pcm_l[15] ? (~pcm_l+16'd1) : pcm_l;
wire [15:0] abs_r=pcm_r[15] ? (~pcm_r+16'd1) : pcm_r;
wire [15:0] stereo_abs=abs_l>abs_r ? abs_l : abs_r;
reg [WINDOW_LOG2-1:0] window_count;
reg [26:0] window_sum;
reg [15:0] window_peak;
wire [26:0] sum_next=window_sum+{11'd0,stereo_abs};
wire [15:0] peak_next=stereo_abs>window_peak ? stereo_abs : window_peak;
wire window_event=audio_valid && (&window_count);
reg stat_valid,normalize_valid,curve_valid,target_valid;
reg [15:0] statistic,target_level,envelope_level;
wire [23:0] amplified={8'd0,statistic}<<GAIN_SHIFT;

wire [23:0] normalized_wide=amplified<=(24'd128<<NORMALIZE_SHIFT) ?
                          (amplified>>NORMALIZE_SHIFT) :
                          24'd64+(amplified>>(NORMALIZE_SHIFT+1));
reg [8:0] normalized_level;
reg [16:0] squared_level;

function [16:0] square_chord;
    input [8:0] value;
    reg [16:0] r;
    begin
        r={12'd0,value[4:0]};
        if(value[8]) square_chord=17'd65536;
        else case(value[7:5])
          0:square_chord=                 (r<<5);
          1:square_chord=17'd1024  +(r<<6)+(r<<5);
          2:square_chord=17'd4096  +(r<<7)+(r<<5);
          3:square_chord=17'd9216  +(r<<8)-(r<<5);
          4:square_chord=17'd16384 +(r<<8)+(r<<5);
          5:square_chord=17'd25600 +(r<<8)+(r<<6)+(r<<5);
          6:square_chord=17'd36864 +(r<<9)-(r<<6)-(r<<5);
          7:square_chord=17'd50176 +(r<<9)-(r<<5);
        endcase
    end
endfunction

wire [22:0] scaled_square=squared_level*MAX_HALF_HEIGHT;
wire [15:0] mapped_target=scaled_square>>(16-AMPLITUDE_SHIFT);
wire [15:0] up_delta=target_level-envelope_level;
wire [15:0] down_delta=envelope_level-target_level;

wire [16:0] attack_step=({1'b0,up_delta}+((1<<ATTACK_SHIFT)-1))>>ATTACK_SHIFT;
wire [16:0] release_step=({1'b0,down_delta}+((1<<RELEASE_SHIFT)-1))>>RELEASE_SHIFT;
wire [15:0] smoothed_next=target_level>envelope_level ?
                         envelope_level+attack_step[15:0] : envelope_level-release_step[15:0];

reg [5:0] history_heights[0:BAR_COUNT-1];
reg [15:0] refresh_count;
wire history_event=frame_tick && refresh_count==UPDATE_FRAMES-1;
integer k;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        window_count<=0;window_sum<=0;window_peak<=0;
        statistic<=0;stat_valid<=0;normalize_valid<=0;curve_valid<=0;
        normalized_level<=0;squared_level<=0;target_level<=0;target_valid<=0;envelope_level<=0;
        sample_seen<=0;de_prev<=0;vs_prev<=0;x_count<=0;y_count<=0;refresh_count<=0;
        if(!HISTORY_RAM)for(k=0;k<BAR_COUNT;k=k+1) history_heights[k]<=0;
    end else begin
        de_prev<=in_de;vs_prev<=in_vs;
        if(in_de) x_count<=x_count+1'b1;else x_count<=0;
        if(de_prev && !in_de)y_count<=y_count+1'b1;
        stat_valid<=0;normalize_valid<=stat_valid;curve_valid<=normalize_valid;target_valid<=curve_valid;
        if(audio_valid) begin
            sample_seen<=1;
            if(window_event) begin
                statistic<=USE_PEAK ? peak_next : (sum_next>>WINDOW_LOG2);
                stat_valid<=1;window_count<=0;window_sum<=0;window_peak<=0;
            end else begin
                window_count<=window_count+1'b1;window_sum<=sum_next;window_peak<=peak_next;
            end
        end

        if(stat_valid) normalized_level<=normalized_wide>=256 ? 9'd256 : normalized_wide[8:0];
        if(normalize_valid) squared_level<=square_chord(normalized_level);
        if(curve_valid) target_level<=mapped_target;
        if(target_valid) envelope_level<=smoothed_next;
        if(frame_tick) begin
            x_count<=0;y_count<=0;sample_seen<=audio_valid;
            if(silent_frame) begin

                window_count<=0;window_sum<=0;window_peak<=0;statistic<=0;stat_valid<=1;
            end
            if(history_event) begin
                refresh_count<=0;
                if(!HISTORY_RAM)begin
                 for(k=0;k<BAR_COUNT-1;k=k+1) history_heights[k]<=history_heights[k+1];
                 history_heights[BAR_COUNT-1]<=envelope_level>>AMPLITUDE_SHIFT;
                end
            end else refresh_count<=refresh_count+1'b1;
        end
    end
end

function [23:0] bar_color;
    input [5:0] index;
    begin
        if(index<(BAR_COUNT+7)/8) bar_color=COLOR_0;
        else if(index<(BAR_COUNT*2+7)/8) bar_color=COLOR_1;
        else if(index<(BAR_COUNT*3+7)/8) bar_color=COLOR_2;
        else if(index<(BAR_COUNT*4+7)/8) bar_color=COLOR_3;
        else if(index<(BAR_COUNT*5+7)/8) bar_color=COLOR_4;
        else if(index<(BAR_COUNT*6+7)/8) bar_color=COLOR_5;
        else if(index<(BAR_COUNT*7+7)/8) bar_color=COLOR_6;
        else bar_color=COLOR_7;
    end
endfunction
wire [10:0] local_x=x_count-PANEL_X;
wire [10:0] local_y=y_count-PANEL_Y;
wire [10:0] bars_x=local_x-LEFT_PAD;
wire panel_hit=!(ECO_ENABLE && eco_active) && in_de && x_count>=PANEL_X && x_count<PANEL_X+PANEL_WIDTH &&
               y_count>=PANEL_Y && y_count<PANEL_Y+PANEL_HEIGHT;
wire slot_hit=panel_hit && local_x>=LEFT_PAD && bars_x<BAR_COUNT*BAR_PITCH;
wire [10:0] full_index=bars_x/BAR_PITCH;
wire [5:0] bar_index=slot_hit ? full_index[5:0] : 6'd0;

wire [5:0] ram_height;wire ram_ready;
generate if(HISTORY_RAM)begin: ram_history
 reg [5:0] mem[0:511];
 reg [5:0] head,clear_index;reg ready;reg [5:0] q;reg ready_q;
 wire [6:0] sum={1'b0,head}+{1'b0,bar_index};
 wire [5:0] address=sum>=BAR_COUNT?sum-BAR_COUNT:sum;
 wire write_enable=!rst && (!ready || history_event);
 wire [8:0] write_address={3'd0,(ready?head:clear_index)};
 wire [5:0] write_height=ready?(envelope_level>>AMPLITUDE_SHIFT):6'd0;
 integer n;initial begin for(n=0;n<512;n=n+1)mem[n]=0;end
 always @(posedge clk or posedge rst)begin
  if(rst)begin head<=0;clear_index<=0;ready<=0;end
  else if(!ready)begin
   if(clear_index==BAR_COUNT-1)ready<=1;
   else clear_index<=clear_index+1'b1;
  end else if(history_event)head<=head==BAR_COUNT-1?6'd0:head+1'b1;
 end
 always @(posedge clk)begin
  q<=mem[{3'd0,address}];ready_q<=ready && !rst;
  if(write_enable)mem[write_address]<=write_height;
 end
 assign ram_height=q;assign ram_ready=ready_q;
end else begin assign ram_height=0;assign ram_ready=0;end endgenerate
wire [6:0] distance_y=local_y<CENTER ? CENTER-1-local_y : local_y-CENTER;
reg [23:0] rgb_p0,color_p0;
reg de_p0,hs_p0,vs_p0,column_p0;
reg [5:0] height_p0;
reg [6:0] distance_p0;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        rgb_p0<=0;color_p0<=0;de_p0<=0;hs_p0<=0;vs_p0<=0;
        column_p0<=0;height_p0<=0;distance_p0<=0;
        out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;
    end else begin
        rgb_p0<=in_rgb;de_p0<=in_de;hs_p0<=in_hs;vs_p0<=in_vs;
        column_p0<=slot_hit && (bars_x%BAR_PITCH)<BAR_WIDTH;
        if(!HISTORY_RAM)height_p0<=history_heights[bar_index];distance_p0<=distance_y;
        color_p0<=bar_color(bar_index);
        out_de<=de_p0;out_hs<=hs_p0;out_vs<=vs_p0;
        out_rgb<=(column_p0 && distance_p0<(HISTORY_RAM?(ram_ready?ram_height:6'd0):height_p0)) ? color_p0 : rgb_p0;
    end
end
endmodule
