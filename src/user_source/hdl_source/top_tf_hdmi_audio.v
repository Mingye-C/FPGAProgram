module top(
    input                       clk,
    input                       rst_n,
    input                       key1,
    input                       key2,
    input                       key3,

	output [5:0]                seg_sel,
	output [7:0]                seg_data,

    input sw1,input sw2,input sw3,input sw4,

    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso,
    input wire btn1_n,btn2_n,btn3_n,ec12_a_n,ec12_b_n,ec12_s_n,
    input wire ec11_a_n, input wire ec11_b_n, input wire ec11_s_n,
    input wire ld2416_out,
    inout wire dht11_data,
    input wire overload_n,input wire fire_n,output wire lcd_cs_n,output wire lcd_bl,output wire lcd_sck,output wire lcd_mosi,output wire lcd_dc,output wire lcd_rst_n,
    input wire gpio_a1_button_n
);

wire [3:0] scene_line;wire [9:0] scene_x;wire [8:0] scene_y;wire [23:0] scene_bg1;wire scene_mask;wire [23:0] floor_rgb;
wire [10:0] scene_ft,scene_sta,scene_stb,scene_pt,scene_pata,scene_patb;wire [7:0] scene_ta,scene_tb;
parameter SCENE_AUDIO_ENABLE=1;
parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 21'd307200;
parameter BUF0_ADDR     = 21'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;
wire playback_auto;
wire [51:0] image_info_data;wire image_info_toggle,image_info_video;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire [1:0] read_active_buf;
wire transition_fast;
wire transition_request_toggle,transition_target_buf,transition_done_toggle,transition_failed;
wire [1:0] video_read_buf_select;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

wire encoder_reset_n,reset_sample_tick;
reset_contact_filter u_encoder_system_reset(.clk(clk),.button_n(ec12_s_n),.reset_n(encoder_reset_n),.sample_tick(reset_sample_tick));
(* dont_touch="true" *) wire system_reset_n=rst_n && encoder_reset_n;

wire sys_pll_lock;
wire video_pll_lock;
wire rst_all;

reg [19:0] rst_cnt = 20'd0;
reg rst_all_reg = 1'b1;

always @(posedge clk) begin
    if (!system_reset_n) begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end else if (!rst_all_reg) begin

        rst_all_reg <= 1'b0;
    end else if (sys_pll_lock && video_pll_lock && hdmi_ref_lock && hdmi_pixel_lock) begin

        if (rst_cnt < 20'd1_000_000) begin
            rst_cnt <= rst_cnt + 1'b1;
            rst_all_reg <= 1'b1;
        end else begin
            rst_all_reg <= 1'b0;
        end
    end else begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end
end

assign rst_all = rst_all_reg;

(* keep="true" *) wire st7789_logo_done,st7789_logo_error;
st7789_display u_st7789(.sample_tick(reset_sample_tick),.clk(clk),.rst(rst_all),.lcd_sck(lcd_sck),.lcd_mosi(lcd_mosi),
 .lcd_dc(lcd_dc),.lcd_rst_n(lcd_rst_n),.lcd_cs_n(lcd_cs_n),.lcd_bl(lcd_bl),.done(st7789_logo_done),.error(st7789_logo_error));

reg [1:0] mem_reset_sync = 2'b11;
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        mem_reset_sync <= 2'b11;
    else
        mem_reset_sync <= {mem_reset_sync[0], 1'b0};
end
wire mem_reset = mem_reset_sync[1];

sys_pll sys_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (sys_pll_lock),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (video_pll_lock),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk)
);

always @(posedge ext_mem_clk or posedge mem_reset) begin
    if (mem_reset)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

wire sd_card_write_ready;

wire hdmi_ref,hdmi_pixel,hdmi_serial,hdmi_ref_lock,hdmi_pixel_lock;
hdmi_ref_pll u_ref(.refclk(clk),.reset(!system_reset_n),.extlock(hdmi_ref_lock),.clk0_out(hdmi_ref),.clk1_out());
hdmi_720_pll u_pixel(.refclk(hdmi_ref),.reset(!system_reset_n||!hdmi_ref_lock),.extlock(hdmi_pixel_lock),.clk0_out(hdmi_pixel),.clk1_out(hdmi_serial));
(* async_reg="true",preserve="true",keep="true" *) reg [1:0] system_reset_sync=3;
always @(posedge hdmi_pixel or negedge system_reset_n)
 if(!system_reset_n)system_reset_sync<=3;else system_reset_sync<={system_reset_sync[0],rst_all};
reg [19:0] hdmi_reset_count=0;reg [1:0] hdmi_locks=0;reg hdmi_reset_hold=1;

wire hdmi_local_reset=!rst_n || system_reset_sync[1];
always @(posedge hdmi_pixel or posedge hdmi_local_reset)begin
 if(hdmi_local_reset)begin hdmi_locks<=0;hdmi_reset_count<=0;hdmi_reset_hold<=1;end
 else begin
  hdmi_locks<={hdmi_locks[0],hdmi_ref_lock&&hdmi_pixel_lock};
  if(hdmi_reset_hold)begin
   if(!hdmi_locks[1])hdmi_reset_count<=0;
   else if(hdmi_reset_count!=999999)hdmi_reset_count<=hdmi_reset_count+1'b1;
   else hdmi_reset_hold<=0;
  end
 end
end
wire hdmi_reset=hdmi_reset_hold;

(* ASYNC_REG="TRUE",preserve="true",keep="true" *)reg[2:0]phy_reset_sync=3'b111;

wire phy_reset_request=hdmi_reset;
always @(posedge hdmi_serial or posedge phy_reset_request)begin
 if(phy_reset_request)phy_reset_sync<=3'b111;else phy_reset_sync<={phy_reset_sync[1:0],1'b0};
end
wire phy_reset=phy_reset_sync[2];
wire hdmi_frame_toggle,scan_line_space;
wire read_line_ready;
wire [23:0] hdmi_rgb;wire hdmi_de,hdmi_sof,hdmi_eol;
wire [31:0] scaler_underflow,scaler_overflow,scan_missed,audio_cdc_overrun;
wire hdmi_audio_valid,hdmi_acr_valid;wire [23:0] hdmi_audio_left,hdmi_audio_right;wire [19:0] hdmi_acr_n,hdmi_acr_cts;

wire speech_req,speech_valid,speech_end,speech_error;wire[31:0]speech_addr;wire[7:0]speech_data;
sd_card_bmp #(.NEXT_KEY_ENABLE(1),.VOICE_ENABLE(1),.EXTERNAL_KEYS(1),
    .CLK_FREQ_HZ       (50_000_000)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_all),
    .audio_clk(video_clk),
    .audio_valid(media_audio_valid),.audio_left(media_audio_left),.audio_right(media_audio_right),
    .acr_valid(acr_valid),.acr_n(acr_n),.acr_cts(acr_cts),
    .audio_underflow_count(audio_underflow_count),.audio_overflow_count(audio_overflow_count),
    .zoom_gray_async(zoom_gray),.extra_skip_press(key_events_sd[2]),.extra_next_press(key_events_sd[0]),.extra_auto_press(key_events_sd[1]),
    .key_next          (key1),
    .key_auto          (key2),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .playback_auto(playback_auto),.image_info_data(image_info_data),.image_info_toggle(image_info_toggle),.image_info_video(image_info_video),

    .write_finish_toggle(frame_write_toggle_mem),
    .read_active_buf(read_active_buf[0]),
    .transition_request_toggle(transition_request_toggle),.transition_target_buf(transition_target_buf),.transition_fast(transition_fast),
    .transition_done_toggle(transition_done_toggle),.transition_failed(transition_failed),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_ready(sd_card_write_ready),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .voice_req(speech_req),.voice_addr(speech_addr),.voice_valid(speech_valid),.voice_end(speech_end),.voice_error(speech_error),.voice_data(speech_data),
    .SD_MISO           (sd_miso)
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (system_reset_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,7'b1111_111}),
    .seg_data_5        ({1'b1,seg_data_0})
);

wire raw_video_read_req;
reg [63:0] read_request_delay;
always @(posedge video_clk or posedge rst_all)
 if(rst_all) read_request_delay<=0;
 else read_request_delay<={read_request_delay[62:0],raw_video_read_req};
assign video_read_req=read_request_delay[63];
widescreen_scan #(.HEIGHT(360)) u_source_scan(.clk(video_clk),.rst(rst_all),.frame_toggle_async(hdmi_frame_toggle),
 .line_space(scan_line_space && read_line_ready),.read_ack(video_read_req_ack),.read_req(raw_video_read_req),
 .hs(hs_0),.vs(vs_0),.de(de_0),.source_y(),.missed_frames(scan_missed));

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

reg [1:0] display_valid_sync;
reg display_valid_frame;
reg vs_prev;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        display_valid_sync <= 2'b00;
        display_valid_frame <= 1'b0;
        vs_prev <= 1'b0;
    end else begin
        display_valid_sync <= {display_valid_sync[0], display_valid};
        vs_prev <= vs;
        if (vs_prev && !vs)
            display_valid_frame <= display_valid_sync[1];
    end
end
assign vout_data = display_valid_frame ? vout_data_raw : 24'h102642;

wire [9:0] transition_mix;
frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .read_line_ready(read_line_ready),
    .mix_config_async(transition_mix),
    .mem_clk           (ext_mem_clk),
    .rst               (mem_reset),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_active_buf(read_active_buf),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (video_read_buf_select),
    .read_len          (21'd230400),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_ready(sd_card_write_ready),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (mem_reset),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

wire signed [7:0] picture_brightness;
wire [8:0] picture_contrast_q8;
wire [3:0] picture_contrast_level;wire picture_mode,picture_reset_notice;
wire picture_change;
wire [23:0] adjusted_rgb;
wire adjusted_de,adjusted_hs,adjusted_vs;
wire[5:0]button_press,button_release;
reg[2:0]key_toggle;always @(posedge clk or posedge rst_all)if(rst_all)key_toggle<=0;else key_toggle<=key_toggle^{(button_press[2]|button_press[5]),(button_press[1]|button_press[4]),(button_press[0]|button_press[3])};
(* ASYNC_REG="TRUE" *)reg[2:0]key_sync0,key_sync1,key_sync2;
always @(posedge sd_card_clk or posedge rst_all)if(rst_all)begin key_sync0<=0;key_sync1<=0;key_sync2<=0;end else begin key_sync0<=key_toggle;key_sync1<=key_sync0;key_sync2<=key_sync1;end
wire[2:0]key_events_sd=key_sync2^key_sync1;
button_event_bank #(.EXTERNAL_TICK(1))u_buttons(.sample_tick(reset_sample_tick),.clk(clk),.rst(rst_all),.buttons_n({btn3_n,btn2_n,btn1_n,key3,key2,key1}),.press(button_press),.release_pulse(button_release));
wire contrast_inc,contrast_dec;
reg zoom_requested;reg[2:0]zoom_gray;
always @(posedge video_clk or posedge rst_all)begin
 if(rst_all)begin zoom_requested<=1;zoom_gray<=1;end
 else begin
  if(contrast_inc&&!contrast_dec&&zoom_requested<1)zoom_requested<=zoom_requested+1'b1;
  else if(contrast_dec&&!contrast_inc&&zoom_requested>0)zoom_requested<=zoom_requested-1'b1;
  zoom_gray<=(zoom_requested>>1)^zoom_requested;
 end
end

ec11_encoder #(.REVERSE_DIRECTION(0))u_ec12(.clk(video_clk),.rst(rst_all),.a_n(ec12_a_n),.b_n(ec12_b_n),.s_n(1'b1),.step_up(contrast_inc),.step_down(contrast_dec),.single_click(),.double_click(),.reset_brightness());
wire encoder_inc,encoder_dec,encoder_single,encoder_double;
ec11_encoder #(.CLICK_ENABLE(1)) u_ec11 (.clk(video_clk),.rst(rst_all),.a_n(ec11_a_n),.b_n(ec11_b_n),.s_n(ec11_s_n),
 .step_up(encoder_inc),.step_down(encoder_dec),.reset_brightness(),.single_click(encoder_single),.double_click(encoder_double));
picture_switch_control #(.TWO_ENCODERS(0),.ENCODER_ENABLE(1),.DUAL_MODE_ENABLE(1)) u_picture_switch (
 .clk(video_clk),.rst(rst_all),.switches({sw4,sw3,sw2,sw1}),.video_vs(vs),
 .contrast_inc(contrast_inc),.contrast_dec(contrast_dec),.contrast_reset(1'b0),
 .encoder_inc(encoder_inc),.encoder_dec(encoder_dec),.encoder_reset(1'b0),.encoder_single(encoder_single),.encoder_double(encoder_double),
 .active_code(),.brightness(picture_brightness),.contrast_q2(),.contrast_q8(picture_contrast_q8),.contrast_level(picture_contrast_level),.adjust_mode(picture_mode),.reset_notice(picture_reset_notice),
 .change_toggle(picture_change));
rgb_picture_adjust #(.CONTRAST_EXT_ENABLE(1)) u_picture_adjust (
 .clk(video_clk),.rst(rst_all),.brightness(picture_brightness),.contrast_q2(3'd4),.contrast_q8(picture_contrast_q8),
 .in_rgb(vout_data),.in_de(de),.in_hs(hs),.in_vs(vs),
 .out_rgb(adjusted_rgb),.out_de(adjusted_de),.out_hs(adjusted_hs),.out_vs(adjusted_vs));
wire [23:0] transition_rgb;
wire transition_de,transition_hs,transition_vs;
video_transition u_video_transition (
    .mix_config(transition_mix),
    .clk(video_clk),.rst(rst_all),
    .request_toggle_async(transition_request_toggle),.target_buf_async(transition_target_buf),.fast_commit_async(transition_fast),
    .read_active_buf_async(read_active_buf),.read_ack_async(video_read_req_ack),
    .frame_read_req(video_read_req),
    .in_rgb(adjusted_rgb),.in_de(adjusted_de),.in_hs(adjusted_hs),.in_vs(adjusted_vs),
    .out_rgb(transition_rgb),.out_de(transition_de),.out_hs(transition_hs),.out_vs(transition_vs),
    .read_buf_select(video_read_buf_select),.done_toggle(transition_done_toggle),
    .transition_failed(transition_failed),.brightness(),.busy()
);

wire eco_active,presence_display,presence_filtered;
wire eco_standby,eco_engaged;wire [6:0] eco_audio_gain;
wire [1:0] scene_mode;wire scene_blink;wire [3:0] scene_floor;
wire external_button_pressed;
wire [12:0] chart_font,floor_font,parameter_font_a,parameter_font_b,subtitle_font_a,subtitle_font_b,page_font_a;
wire [14:0] subtitle_cn_a,subtitle_cn_b,page_cn_a;
wire [7:0] shared_ascii_a,shared_ascii_b;wire shared_cn_a,shared_cn_b;
wire eco_on=eco_standby && scene_mode==0;
presence_eco_controller u_presence(.clk(video_clk),.rst(rst_all),.presence_async(ld2416_out),.scene_mode(scene_mode),.video_vs(vs),.presence_display(presence_display),.eco_active(eco_active),.presence_filtered(presence_filtered));
scene_controller #(.SENSOR_ENABLE(1)) u_scene_control(.overload_n(overload_n),.fire_n(fire_n),.clk(video_clk),.rst(rst_all),.pressed(external_button_pressed),.video_vs(vs),.scene_mode(scene_mode),.blink(scene_blink),.short_event(),.long_event());
wire [10:0] native_x;wire [9:0] native_y;
wire native_up;wire [4:0] native_slide;wire [10:0] native_phase;wire native_chinese;
wire native_osd_on,native_reset,native_info_valid,native_video;wire [7:0] native_brightness,native_numbers;wire [3:0] native_contrast;wire [63:0] native_info;
wire [1:0] native_eco_state;wire [5:0] native_eco_depth;
wire [23:0] layout_rgb;
wire layout_de,layout_hs,layout_vs;
elevator_status_osd #(.NATIVE_TEXT(1),.SCENE_ENABLE(1),.EXTERNAL_FONT_ENABLE(1),.ECO_ENABLE(1)) u_elevator_status(.native_up(native_up),.native_slide(native_slide),
 .clk(video_clk),.rst(rst_all),.eco_active(eco_on),.scene_mode(scene_mode),.scene_blink(scene_blink),.scene_line_code(scene_line),.raster_x(scene_x),.raster_y(scene_y),.background_p1(scene_bg1),.current_floor(scene_floor),
 .text_request(scene_ft),.external_text(scene_ta),.font_request(floor_font),.external_font_row(shared_ascii_a),
 .in_rgb(transition_rgb),.in_de(transition_de),.in_hs(transition_hs),.in_vs(transition_vs),
 .out_rgb(floor_rgb),.out_de(layout_de),.out_hs(layout_hs),.out_vs(layout_vs));

wire [23:0] waveform_rgb;
wire waveform_de,waveform_hs,waveform_vs;
audio_waveform_overlay #(
    .HISTORY_RAM(1),.ECO_ENABLE(1),
    .PANEL_X(510),.PANEL_Y(28),.PANEL_WIDTH(120),.PANEL_HEIGHT(38),
    .BAR_COUNT(48),.BAR_WIDTH(1),.MAX_HALF_HEIGHT(18),.WINDOW_LOG2(10),.GAIN_SHIFT(3),
    .ATTACK_SHIFT(1),.RELEASE_SHIFT(3),.UPDATE_FRAMES(2)
) u_audio_waveform (
    .clk(video_clk),.rst(rst_all),
    .eco_active(eco_on),.audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),
    .in_rgb(layout_rgb),.in_de(layout_de),.in_hs(layout_hs),.in_vs(layout_vs),
    .out_rgb(waveform_rgb),.out_de(waveform_de),.out_hs(waveform_hs),.out_vs(waveform_vs)
);

wire [23:0] spectrum_rgb;
wire spectrum_de,spectrum_hs,spectrum_vs;
fft_spectrum_overlay #(
 .NATIVE_TEXT(1),
 .EXTERNAL_FONT_ENABLE(1),.ECO_ENABLE(1),
 .PANEL_X(400),.PANEL_Y(28),.PANEL_WIDTH(105),.PANEL_HEIGHT(37),
 .BAR_X(405),.BAR_BOTTOM(64),.BAR_WIDTH(2),.BAR_GAP(2),.MAX_HEIGHT(70),.DISPLAY_SCALE_NUM(1),.DISPLAY_SCALE_SHIFT(1),.TITLE_Y(282),.FFT_TITLE_X(210),.LEVEL_TITLE_X(457),.GAIN_SHIFT(1),.LOG_FLOOR_Q3(24),
 .HEIGHT_GAIN(1),.DECAY_STEP(2)
) u_fft_spectrum (.font_request(chart_font),.external_font(shared_ascii_a),
 .clk(video_clk),.rst(rst_all),
 .eco_active(eco_on),.audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),
 .in_rgb(waveform_rgb),.in_de(waveform_de),.in_hs(waveform_hs),.in_vs(waveform_vs),
 .out_rgb(spectrum_rgb),.out_de(spectrum_de),.out_hs(spectrum_hs),.out_vs(spectrum_vs));

wire [23:0] subtitle_rgb;
wire subtitle_de,subtitle_hs,subtitle_vs;

wire subtitle_enable=1'b1;
scrolling_subtitle #(
    .NATIVE_TEXT(1),
    .SCENE_ENABLE(1),.EXTERNAL_FONT_ENABLE(1),
    .VIDEO_WIDTH(640), .VIDEO_HEIGHT(360),
    .CLIP_X(160),.CLIP_WIDTH(470),.TEXT_Y(337),
    .TEXT_LEN(41),
    .TEXT("WELCOME TO FPGA MULTIMEDIA DISPLAY SYSTEM"),
    .FG_COLOR(24'hffffff), .SHADOW_ENABLE(1'b1), .SHADOW_COLOR(24'h000000),
    .FRAMES_PER_STEP(1), .STEP_PIXELS(1)
) u_scrolling_subtitle (.native_phase(native_phase),.native_chinese(native_chinese),
    .clk(video_clk), .rst(rst_all), .enable(subtitle_enable && !eco_on),.scene_mode(scene_mode),
    .text_a_request(scene_sta),.text_b_request(scene_stb),.external_text_a(scene_ta),.external_text_b(scene_tb),.font_a_request(subtitle_font_a),.font_b_request(subtitle_font_b),.chinese_a_request(subtitle_cn_a),.chinese_b_request(subtitle_cn_b),
    .external_font_a(shared_ascii_a),.external_font_b(shared_ascii_b),.external_chinese_a(shared_cn_a),.external_chinese_b(shared_cn_b),
    .in_rgb(spectrum_rgb), .in_de(spectrum_de), .in_hs(spectrum_hs), .in_vs(spectrum_vs),
    .out_rgb(subtitle_rgb), .out_de(subtitle_de),
    .out_hs(subtitle_hs), .out_vs(subtitle_vs)
);

wire [23:0] parameter_rgb;
wire parameter_de,parameter_hs,parameter_vs;
external_button_level #(.DEBOUNCE_CYCLES(500000)) u_external_button (
 .clk(video_clk),.rst(rst_all),.button_n(gpio_a1_button_n),.pressed(external_button_pressed));
picture_parameter_osd #(.NATIVE_TEXT(1),.SCENE_ENABLE(1),.EXTERNAL_FONT_ENABLE(1),.ECO_ENABLE(1),.OSD_X(166),.OSD_Y(12),.BUTTON_STATUS_ENABLE(0),.DUAL_MODE_ENABLE(1)) u_picture_osd (.native_osd_on(native_osd_on),.native_reset(native_reset),.native_brightness(native_brightness),.native_contrast(native_contrast),.native_info(native_info),.native_numbers(native_numbers),.native_info_valid(native_info_valid),.native_video(native_video),
 .clk(video_clk),.rst(rst_all),.eco_active(eco_on),.scene_mode(scene_mode),.text_a_request(scene_pata),.text_b_request(scene_patb),.external_text_a(scene_ta),.external_text_b(scene_tb),.font_a_request(parameter_font_a),.font_b_request(parameter_font_b),.external_font_a(shared_ascii_a),.external_font_b(shared_ascii_b),.button_pressed(external_button_pressed),.change_toggle(picture_change),
 .brightness(picture_brightness),.contrast_q2(3'd4),.contrast_level(picture_contrast_level),.adjust_mode(picture_mode),.reset_notice(picture_reset_notice),
 .image_info_toggle_async(image_info_toggle),.image_info_data_async(image_info_data),.image_video_async(image_info_video),
 .in_rgb(subtitle_rgb),.in_de(subtitle_de),.in_hs(subtitle_hs),.in_vs(subtitle_vs),
 .out_rgb(parameter_rgb),.out_de(parameter_de),.out_hs(parameter_hs),.out_vs(parameter_vs));

assign shared_ascii_a=0;assign shared_ascii_b=0;assign shared_cn_a=0;assign shared_cn_b=0;assign scene_ta=32;assign scene_tb=32;
wire [23:0] scene_rgb;wire scene_de,scene_hs,scene_vs;
assign layout_rgb=scene_mask?scene_rgb:floor_rgb;
scene_overlay #(.NATIVE_TEXT(1),.EXTERNAL_TEXT_ENABLE(1),.PARALLEL(1),.ECO_ENABLE(1),.ECO_TEXT_X(378),.ECO_TEXT_Y(320),.ECO_TITLE_ENABLE(1)) u_scene_overlay(.clk(video_clk),.rst(rst_all),.scene_mode(scene_mode),.blink(scene_blink),.eco_active(eco_on),.presence_display(presence_display),
 .line_descriptor(scene_line),.raster_x(scene_x),.raster_y(scene_y),.background_p1(scene_bg1),.out_mask(scene_mask),.in_rgb(transition_rgb),.in_de(transition_de),.in_hs(transition_hs),.in_vs(transition_vs),
 .text_request(scene_pt),.external_text(scene_ta),.font_request(page_font_a),.chinese_request(page_cn_a),.ascii_row(shared_ascii_a),.chinese_pixel(shared_cn_a),
 .out_rgb(scene_rgb),.out_de(scene_de),.out_hs(scene_hs),.out_vs(scene_vs));

wire [23:0] eco_visual_rgb;wire eco_visual_de,eco_visual_hs,eco_visual_vs;
eco_visual_transition #(.RADAR_ENABLE(1),.RADAR_STYLE(2)) u_eco_visual(
 .clk(video_clk),.rst(rst_all),.scene_mode(scene_mode),.request_eco(eco_active),.presence(presence_filtered),
 .in_rgb(parameter_rgb),.in_de(parameter_de),.in_hs(parameter_hs),.in_vs(parameter_vs),
 .standby(eco_standby),.engaged(eco_engaged),.audio_gain(eco_audio_gain),.state_debug(native_eco_state),.depth_debug(native_eco_depth),
 .out_rgb(eco_visual_rgb),.out_de(eco_visual_de),.out_hs(eco_visual_hs),.out_vs(eco_visual_vs));
widescreen_line_scaler #(.DOUBLE(1)) u_scaler(.source_clk(video_clk),.source_rst(rst_all),
 .source_de(eco_visual_de),.source_rgb(eco_visual_rgb),.line_space(scan_line_space),
 .output_clk(hdmi_pixel),.output_rst(hdmi_reset),.frame_toggle(hdmi_frame_toggle),
 .rgb(hdmi_rgb),.de(hdmi_de),.sof(hdmi_sof),.eol(hdmi_eol),
 .underflow_count(scaler_underflow),.overflow_count(scaler_overflow),.output_x(),.output_y(),.pixel_x(native_x),.pixel_y(native_y));

wire dht_drive_low,dht_valid,dht_update,dht_ack;
wire[15:0]dht_bcd;wire[2:0]dht_status,dht_failures;
assign dht11_data=dht_drive_low?1'b0:1'bz;
dht11_reader u_dht11(.clk(clk),.rst(rst_all),.slow_tick(reset_sample_tick),
 .data_in(dht11_data),.status_ack(dht_ack),.drive_low(dht_drive_low),.bcd(dht_bcd),.valid(dht_valid),
 .update_toggle(dht_update),.status(dht_status),.failures(dht_failures));
wire[16:0]dht_native;
dht11_status_cdc u_dht_state(.clk(hdmi_pixel),.rst(hdmi_reset),.update_toggle(dht_update),
 .held({dht_valid,dht_bcd}),.install_frame(native_x==0 && native_y==748),.active(dht_native),.ack(dht_ack));

(* async_reg="true" *) reg[1:0]auto_sync;
always @(posedge video_clk or posedge rst_all)if(rst_all)auto_sync<=3;else auto_sync<={auto_sync[0],playback_auto};
wire [124:0] native_state;
wire [23:0] final_rgb;wire final_de,final_sof,final_eol;
ui_state_cdc #(.WIDTH(125)) u_ui_state(.sclk(video_clk),.srst(rst_all),.source_vs(vs),
 .source_state({auto_sync[1],scene_mode,scene_blink,eco_on,native_eco_state,native_eco_depth,presence_display,scene_floor,native_up,native_slide,native_phase,native_chinese,subtitle_enable,native_brightness,native_contrast,native_osd_on,native_reset,native_info,native_numbers,native_info_valid,native_video}),
 .dclk(hdmi_pixel),.drst(hdmi_reset),.install_frame(native_x==0 && native_y==748),.active_state(native_state));
native_text_overlay u_native_text(.sensor_state(dht_native),.clk(hdmi_pixel),.rst(hdmi_reset),.state(native_state),.x(native_x),.y(native_y),
 .in_rgb(hdmi_rgb),.in_de(hdmi_de),.in_sof(hdmi_sof),.in_eol(hdmi_eol),
 .out_rgb(final_rgb),.out_de(final_de),.out_sof(final_sof),.out_eol(final_eol));
hdmi_audio_cdc u_audio_cdc(.sclk(video_clk),.srst(rst_all),.svalid(audio_valid),.sl(audio_left),.sr(audio_right),
 .dclk(hdmi_pixel),.drst(hdmi_reset),.valid(hdmi_audio_valid),.left(hdmi_audio_left),.right(hdmi_audio_right),
 .acr_valid(hdmi_acr_valid),.acr_n(hdmi_acr_n),.acr_cts(hdmi_acr_cts),.overrun(audio_cdc_overrun));
startup_pulse #(.CNT_MAX(100000)) u_startup_pulse(.I_clk(hdmi_pixel),.I_rst(hdmi_reset),.O_pulse(edid_trig));

hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 1650        ),
    .HSA                    ( 40         ),
    .HFP                    ( 110         ),
    .HBP                    ( 220         ),
    .HACTIVE                ( 1280        ),
    .VTOTAL                 ( 750        ),
    .VSA                    ( 5          ),
    .VFP                    ( 5         ),
    .VBP                    ( 20         ),
    .VACTIVE                ( 720        ),
    .VIDEO_VIC              ( 4          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 743        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (hdmi_pixel),
    .I_rst              (hdmi_reset),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (final_sof),
    .I_axis_s_valid     (final_de),
    .I_axis_s_last      (final_eol),
    .I_axis_s_data      (final_rgb),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (hdmi_audio_valid),
    .I_audio_left_data  (hdmi_audio_left),
    .I_audio_right_data (hdmi_audio_right),
    .I_acr_valid        (hdmi_acr_valid),
    .I_acr_cts          (hdmi_acr_cts),
    .I_acr_n            (hdmi_acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

wire media_audio_valid;wire [23:0] media_audio_left,media_audio_right;
generate if(SCENE_AUDIO_ENABLE)begin
 wire announcement_valid;wire[23:0]announcement_left,announcement_right;wire[7:0]speech_underflows;
direction_voice u_direction_voice(.sclk(sd_card_clk),.srst(rst_all),.aclk(video_clk),.arst(rst_all),.direction_up(native_up),.scene(scene_mode),.eco(eco_on),
.in_valid(media_audio_valid),.in_left(media_audio_left),.in_right(media_audio_right),.out_valid(announcement_valid),.out_left(announcement_left),.out_right(announcement_right),
.read_req(speech_req),.read_addr(speech_addr),.read_data(speech_data),.read_valid(speech_valid),.read_end(speech_end),.read_error(speech_error),.underflows(speech_underflows));
 scene_audio_mix #(.ECO_ENABLE(1),.ECO_ANIMATION_ENABLE(1)) u_scene_audio(.eco_animation_gain(eco_audio_gain),.eco_mute(eco_on),.clk(video_clk),.rst(rst_all),.scene_mode(scene_mode),.in_valid(announcement_valid),.in_left(announcement_left),.in_right(announcement_right),.out_valid(audio_valid),.out_left(audio_left),.out_right(audio_right));
end else begin
 assign audio_valid=media_audio_valid;assign audio_left=media_audio_left;assign audio_right=media_audio_right;
end endgenerate
wire audio_valid;
wire [23:0] audio_left;
wire [23:0] audio_right;
wire acr_valid;
wire [19:0] acr_n;
wire [19:0] acr_cts;

wire [31:0] audio_underflow_count  ;
wire [31:0] audio_overflow_count  ;

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (hdmi_pixel),
    .I_serial_clk       (hdmi_serial),
    .I_rst              (phy_reset),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
