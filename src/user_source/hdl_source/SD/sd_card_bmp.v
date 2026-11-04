module sd_card_bmp #(
    parameter integer NEXT_KEY_ENABLE=0,parameter integer EXTERNAL_KEYS=0,parameter integer VOICE_ENABLE=0,
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter integer VIDEO_PERIOD_CYCLES = CLK_FREQ_HZ/12,
    parameter integer VIDEO_SRC_W = 352,
    parameter integer VIDEO_SRC_H = 220,
    parameter integer VIDEO_FRAMES=299, FRAME_BITS=9, POSITION_BITS=20,
    parameter integer VIDEO_FPS=15,PROGRAM1_FRAMES=243,PROGRAM2_FRAMES=223,SAMPLES_PER_FRAME=3200
)(
    input                       clk,
    input                       rst,
    input audio_clk,
    output audio_valid,output [23:0] audio_left,output [23:0] audio_right,
    output acr_valid,output [19:0] acr_n,output [19:0] acr_cts,
    output [31:0] audio_underflow_count,output [31:0] audio_overflow_count,
    input [2:0]zoom_gray_async,
    input extra_skip_press,input extra_next_press,extra_auto_press,
    input                       key_next,
    input                       key_auto,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output wire playback_auto,
    output reg                  display_valid,
    output reg [51:0] image_info_data,output reg image_info_toggle,output image_info_video,
    output      [3:0]           state_code,

    input                       write_finish_toggle,
    input read_active_buf,
    output reg transition_request_toggle,
    output transition_target_buf,
    output reg transition_fast,
    input transition_done_toggle,
    input transition_failed,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    input write_ready,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input voice_req,input[31:0]voice_addr,output voice_valid,voice_end,voice_error,output[7:0]voice_data,
    input                       SD_MISO
);

(* ASYNC_REG="TRUE" *) reg [1:0] write_ack_sync;
wire safe_write_ack=write_ack_sync[1];
always @(posedge clk or posedge rst)begin
 if(rst)write_ack_sync<=0;else write_ack_sync<={write_ack_sync[0],write_req_ack};
end
localparam integer SERIAL_BITS=(FRAME_BITS+2<5)?5:FRAME_BITS+2;
wire key_next_press;
wire key_auto_press;
wire media_skip_press=NEXT_KEY_ENABLE && extra_skip_press;
reg manual_next_pending;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire [3:0]       state_code_i;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire index_done, index_failed;
wire [3:0] index_error;
wire [3:0] index_count;
wire [287:0] index_lbas, index_sizes;
wire[3:0] image_lookup_slot;

(*async_reg="true"*)reg zoom_g0,zoom_g1;
always @(posedge clk or posedge rst)if(rst)begin zoom_g0<=1;zoom_g1<=1;end else begin zoom_g0<=zoom_gray_async[0];zoom_g1<=zoom_g0;end
wire zoom_sd=zoom_g1;
reg load_zoom,image_zoom_applied;
wire zoom_dirty=zoom_sd!=image_zoom_applied;
wire zoom_reload=zoom_dirty&&!manual_next_pending&&!next_req_pending;
wire[3:0] image_lookup_target=(!first_image_committed)?0:((return_needed || display_is_video || zoom_reload)?img_idx:next_from_current);
wire[31:0] image_lookup_lba,image_lookup_size;wire image_lookup_valid;
wire index_read, bmp_read_req;
wire [31:0] index_addr, bmp_addr;
wire bmp_done, bmp_failed;
reg load_start_pulse;
reg [31:0] load_sector, load_size;
reg fatal_error;
reg [1:0] read_active_sync;
wire index_ready = index_done && !index_failed && !fatal_error;
wire index_data_valid,index_read_end,bmp_data_valid,bmp_read_end;
wire wav_req,wav_data_valid,wav_read_end,wav_bus_error,bmp_bus_error;
wire [31:0] wav_addr;
wire wav_present,wav_header_valid,wav_failed;
wire [31:0] wav_lba,wav_size,wav_offset,wav_length;
wire [3:0] wav_error;
wire transport_failed;
wire [11:0] audio_wr_level,audio_rd_level;
wire audio_fifo_full,audio_fifo_empty,audio_fifo_write,audio_fifo_read;
wire [31:0] audio_pcm,audio_fifo_data;
wire [31:0] wav_loop_count  ;
wire [31:0] audio_sector_count  ;
wire [31:0] bmp_sector_count  ;
wire [31:0] max_sector_cycles  ;
wire [2:0] sector_owner;
wire video_present,video_header_valid,video_failed,video_read_req,video_data_valid,video_read_end,video_bus_error;
wire [31:0] video_lba,video_size,video_addr;
wire video_pixel_valid,video_pixel_ready,video_source_done,video_composed_done;
wire [15:0] video_pixel;
wire video_write_en,bmp_write_en,bmp_write_req;
wire [31:0] video_write_data,bmp_write_data;
reg[1:0] current_program;reg program_switch_pending,program_to_first,program_audio_token,program_end_seen;
reg[4:0]program_reset_count;reg[1:0]program_end_sync;wire program_end;wire[1:0]audio_program;
wire video_reader_reset=rst || program_reset_count!=0;
wire[FRAME_BITS-1:0] program_frames=current_program==0?VIDEO_FRAMES:current_program==1?PROGRAM1_FRAMES:PROGRAM2_FRAMES;
reg desired_video,display_is_video,load_is_video,return_needed,cancel_picture;
reg video_write_req,video_kick_pending,video_frame_start;
reg video_restart_pending,discard_standby;
reg [FRAME_BITS-1:0] video_frame_index;
reg [$clog2(CLK_FREQ_HZ)-1:0] video_second_clock;
reg [SERIAL_BITS-1:0] video_loaded_serial,video_display_serial;
reg [FRAME_BITS-1:0] video_display_frame;
reg first_video_arm,first_video_token;
wire video_wav_present;
wire [31:0] video_wav_lba,video_wav_size;
wire audio_selected_video,audio_reader_reset,audio_fifo_reset,audio_reader_start;
wire audio_allow_request,audio_prepared,audio_source_failed,audio_session_reset,hdmi_quiescent;
wire timeline_play_enable,timeline_running,timeline_req;
wire [31:0] timeline_serial,timeline_loop_count;
wire [FRAME_BITS-1:0] timeline_frame;
wire [POSITION_BITS-1:0] timeline_sample_position;
reg [1:0] timeline_req_sync,timeline_running_sync;
reg timeline_ack,timeline_capture;
reg [SERIAL_BITS-1:0] audio_frame_serial;
reg [FRAME_BITS-1:0] audio_frame_index;

localparam integer VIDEO_TICK_BITS=(CLK_FREQ_HZ>=1000000)?16:6;
localparam integer VIDEO_QUANTUM=1<<VIDEO_TICK_BITS;
localparam integer VIDEO_SLOT_TICKS=(CLK_FREQ_HZ/VIDEO_FPS)/VIDEO_QUANTUM;
localparam integer VIDEO_SAFE_SLOT_TICKS=VIDEO_SLOT_TICKS<1?1:VIDEO_SLOT_TICKS;
localparam integer VIDEO_GUARD_TICKS=(CLK_FREQ_HZ/59+VIDEO_QUANTUM-1)/VIDEO_QUANTUM+6;
reg [8:0] video_prepare_ticks,video_prepare_max;
reg [7:0] video_slot_ticks;
reg [2:0] video_phase_serial;
reg video_prepare_recorded;
wire video_measure_tick=(video_second_clock[VIDEO_TICK_BITS-1:0]==0);
wire [9:0] video_predict_ticks={2'd0,video_slot_ticks}+{1'b0,video_prepare_max}+VIDEO_GUARD_TICKS;
wire [2:0] video_predict_lead=video_predict_ticks>=VIDEO_SAFE_SLOT_TICKS*6?3'd6:
                              video_predict_ticks>=VIDEO_SAFE_SLOT_TICKS*5?3'd5:
                              video_predict_ticks>=VIDEO_SAFE_SLOT_TICKS*4?3'd4:
                              video_predict_ticks>=VIDEO_SAFE_SLOT_TICKS*3?3'd3:
                              video_predict_ticks>=VIDEO_SAFE_SLOT_TICKS*2?3'd2:
                              video_predict_ticks>=VIDEO_SAFE_SLOT_TICKS?3'd1:3'd0;
wire [SERIAL_BITS-1:0] video_predict_serial=audio_frame_serial+video_predict_lead;
wire [FRAME_BITS:0] video_predict_frame_sum={1'b0,audio_frame_index}+video_predict_lead;
wire [FRAME_BITS-1:0] video_predict_frame=video_predict_frame_sum>=program_frames?video_predict_frame_sum-program_frames:video_predict_frame_sum[FRAME_BITS-1:0];

wire video_choose_predicted=display_frame_behind || video_predict_lead!=0;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  video_prepare_ticks<=2;video_prepare_max<=VIDEO_SAFE_SLOT_TICKS;
  video_slot_ticks<=1;video_phase_serial<=0;video_prepare_recorded<=0;
 end else begin
  if(!audio_selected_video || !timeline_running_sync[1] || audio_frame_serial[2:0]!=video_phase_serial)begin
   video_slot_ticks<=1;video_phase_serial<=audio_frame_serial[2:0];
  end else if(video_measure_tick && video_slot_ticks<VIDEO_SAFE_SLOT_TICKS)video_slot_ticks<=video_slot_ticks+1'b1;
  if(!desired_video || audio_session_reset)begin
   video_prepare_max<=VIDEO_SAFE_SLOT_TICKS;video_prepare_ticks<=2;video_prepare_recorded<=0;
  end else if(!load_busy || !load_is_video)begin
   video_prepare_ticks<=2;video_prepare_recorded<=0;
  end else if(!video_prepare_recorded)begin
   if(source_done_seen && write_done_seen)begin
    video_prepare_recorded<=1;

    video_prepare_max<=video_prepare_ticks;
   end else if(video_measure_tick && !(&video_prepare_ticks))video_prepare_ticks<=video_prepare_ticks+1'b1;
  end
 end
end

localparam integer VIDEO_COMMIT_CUTOFF=(VIDEO_SAFE_SLOT_TICKS>VIDEO_GUARD_TICKS)?
                                      VIDEO_SAFE_SLOT_TICKS-VIDEO_GUARD_TICKS:0;
wire loaded_frame_deadline_risk=timeline_running_sync[1] && video_loaded_serial!=0 &&
                              video_phase_serial==audio_frame_serial[2:0] &&
                              video_slot_ticks>=VIDEO_COMMIT_CUTOFF &&
                              $signed(audio_frame_serial-video_loaded_serial)>=0;
wire loaded_frame_stale=$signed(audio_frame_serial-video_loaded_serial)>0;
wire loaded_frame_due=$signed(audio_frame_serial-video_loaded_serial)>=0;
wire display_frame_behind=$signed(audio_frame_serial-video_display_serial)>0;

always @(posedge clk or posedge rst)begin
 if(rst)begin timeline_req_sync<=0;timeline_running_sync<=0;timeline_ack<=0;timeline_capture<=0;audio_frame_serial<=0;audio_frame_index<=0;end
 else begin
  timeline_req_sync<={timeline_req_sync[0],timeline_req};
  timeline_running_sync<={timeline_running_sync[0],timeline_running};
  if(timeline_req_sync[1]!=timeline_ack && !timeline_capture)timeline_capture<=1;
  if(timeline_capture)begin
   timeline_capture<=0;timeline_ack<=timeline_req_sync[1];
   if(audio_prepared && audio_selected_video)begin audio_frame_serial<=timeline_serial;audio_frame_index<=timeline_frame;end
  end
  if(!audio_prepared || !audio_selected_video)begin audio_frame_serial<=0;audio_frame_index<=0;end
 end
end
audio_source_control #(.PCM0_BYTES(VIDEO_FRAMES*SAMPLES_PER_FRAME*4),.PCM1_BYTES(PROGRAM1_FRAMES*SAMPLES_PER_FRAME*4),.PCM2_BYTES(PROGRAM2_FRAMES*SAMPLES_PER_FRAME*4)) u_audio_source(
 .clk(clk),.rst(rst),.index_ready(index_done && !index_failed),.desired_video(desired_video),.desired_program(current_program),.restart_toggle(program_audio_token),.selected_program(audio_program),
 .background_present(wav_present),.soundtrack_present(video_wav_present),
 .sector_owner(sector_owner),.hdmi_quiescent_async(hdmi_quiescent),
 .header_valid(wav_header_valid),.reader_failed(wav_failed),.transport_failed(transport_failed),
 .data_length(wav_length),.fifo_used(audio_wr_level),.selected_video(audio_selected_video),
 .reader_reset(audio_reader_reset),.fifo_reset(audio_fifo_reset),.reader_start(audio_reader_start),
 .allow_request(audio_allow_request),.prepared(audio_prepared),.failed(audio_source_failed),.session_reset(audio_session_reset));
av_audio_timeline #(.FRAME_COUNT(VIDEO_FRAMES),.PROGRAM1_FRAMES(PROGRAM1_FRAMES),.PROGRAM2_FRAMES(PROGRAM2_FRAMES),.SAMPLES_PER_FRAME(SAMPLES_PER_FRAME),.FRAME_BITS(FRAME_BITS),.SERIAL_BITS(SERIAL_BITS),.POSITION_BITS(POSITION_BITS)) u_audio_timeline(
 .clk(audio_clk),.rst(rst),.program_select_async(audio_program),.program_end(program_end),.session_reset_async(audio_session_reset),.prepared_async(audio_prepared),
 .selected_video_async(audio_selected_video),.first_arm_async(first_video_arm),.first_token_async(first_video_token),
 .first_commit_toggle(transition_done_toggle),.pcm_consume(audio_fifo_read),.snapshot_ack_async(timeline_ack),
 .play_enable(timeline_play_enable),.running(timeline_running),.snapshot_req(timeline_req),
 .snapshot_serial(timeline_serial),.snapshot_frame(timeline_frame),.loop_count(timeline_loop_count),.sample_position(timeline_sample_position));
(* keep="true" *) reg [31:0] video_late_count,video_missed_slots,video_loop_count,video_frames_displayed;
(* keep="true" *) reg [7:0] video_actual_fps;
reg [7:0] video_fps_accum;
assign write_req=load_is_video ? video_write_req : bmp_write_req;
assign write_en=load_busy && (load_is_video ? video_write_en : bmp_write_en);
assign write_data=load_is_video ? video_write_data : bmp_write_data;
wire audio_playing;
assign voice_data=sd_sec_read_data;
media_sector_arbiter #(.VOICE_ENABLE(VOICE_ENABLE),.TIMEOUT_CYCLES(CLK_FREQ_HZ/100)) u_sector_arbiter (
    .clk(clk),.rst(rst),.initialized(sd_init_done),.index_done(index_done),
    .index_req(index_read),.index_addr(index_addr),.index_valid(index_data_valid),.index_end(index_read_end),
    .audio_req(wav_req && audio_allow_request),.audio_addr(wav_addr),.audio_valid(wav_data_valid),.audio_end(wav_read_end),.audio_error(wav_bus_error),
    .bmp_req(bmp_read_req && !fatal_error && !bmp_failed && load_busy && !load_is_video),.bmp_addr(bmp_addr),
    .bmp_valid(bmp_data_valid),.bmp_end(bmp_read_end),.bmp_error(bmp_bus_error),
    .video_req(video_read_req),.video_addr(video_addr),.video_valid(video_data_valid),.video_end(video_read_end),.video_error(video_bus_error),
    .voice_req(voice_req),.voice_addr(voice_addr),.voice_valid(voice_valid),.voice_end(voice_end),.voice_error(voice_error),
    .fifo_level(audio_wr_level),.sd_req(sd_sec_read),.sd_addr(sd_sec_read_addr),
    .sd_valid(sd_sec_read_data_valid),.sd_end(sd_sec_read_end),.transport_failed(transport_failed),
    .active_owner(sector_owner),.max_sector_cycles(max_sector_cycles),.audio_sectors(audio_sector_count),.bmp_sectors(bmp_sector_count)
);
wav_stream_reader u_wav_reader (
    .clk(clk),.rst(audio_reader_reset),.start(audio_reader_start),
    .start_lba(audio_selected_video ? video_wav_lba : wav_lba),.file_size(audio_selected_video ? video_wav_size : wav_size),.read_req(wav_req),.read_addr(wav_addr),
    .read_data(sd_sec_read_data),.read_valid(wav_data_valid),.read_end(wav_read_end),.read_error(wav_bus_error),
    .fifo_used(audio_wr_level),.fifo_full(audio_fifo_full),.pcm_write(audio_fifo_write),.pcm_data(audio_pcm),
    .header_valid(wav_header_valid),.failed(wav_failed),.error_code(wav_error),
    .data_offset(wav_offset),.data_length(wav_length),.loop_count(wav_loop_count),.overflow_count(audio_overflow_count)
);

wfifo_32_32_512 #(.ADDR_WIDTH_W(12),.ADDR_WIDTH_R(12),.AL_FULL_NUM(4090),.AL_EMPTY_NUM(128)) u_audio_fifo (
    .rst(audio_fifo_reset),.clkw(clk),.clkr(audio_clk),.we(audio_fifo_write),.di(audio_pcm),
    .re(audio_fifo_read),.dout(audio_fifo_data),.full_flag(audio_fifo_full),.empty_flag(audio_fifo_empty),
    .wrusedw(audio_wr_level),.rdusedw(audio_rd_level),.valid(),.afull(),.aempty()
);
hdmi_wav_audio u_wav_audio (
    .clk(audio_clk),.rst(rst),.source_ready_async(timeline_play_enable),
    .fifo_data(audio_fifo_data),.fifo_empty(audio_fifo_empty),.fifo_used(audio_rd_level),.fifo_read(audio_fifo_read),
    .audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),
    .acr_valid(acr_valid),.acr_n(acr_n),.acr_cts(acr_cts),.underflow_count(audio_underflow_count),.playing(audio_playing),.quiescent(hdmi_quiescent)
);
localparam integer VRAW_SLOT_BYTES=((VIDEO_SRC_W*VIDEO_SRC_H*2+511)/512+2)*512;
media_index_reader #(.VIDEO_FILE_SIZE(512+VIDEO_FRAMES*VRAW_SLOT_BYTES),.VIDEO_FILE1_SIZE(512+PROGRAM1_FRAMES*VRAW_SLOT_BYTES),.VIDEO_FILE2_SIZE(512+PROGRAM2_FRAMES*VRAW_SLOT_BYTES),.WAV_FILE0_SIZE(44+VIDEO_FRAMES*SAMPLES_PER_FRAME*4),.WAV_FILE1_SIZE(44+PROGRAM1_FRAMES*SAMPLES_PER_FRAME*4),.WAV_FILE2_SIZE(44+PROGRAM2_FRAMES*SAMPLES_PER_FRAME*4),.TIMEOUT_CYCLES(CLK_FREQ_HZ*2)) u_index (
    .clk(clk), .rst(rst), .start(1'b1), .sd_init_done(sd_init_done),.program_select(current_program),
    .sd_sec_read(index_read), .sd_sec_read_addr(index_addr),
    .sd_sec_read_data(sd_sec_read_data),
    .sd_sec_read_data_valid(index_data_valid),
    .sd_sec_read_end(index_read_end),
    .done(index_done), .failed(index_failed), .error_code(index_error),
    .image_count(index_count), .image_lbas(), .image_sizes(),
    .image_select(image_lookup_target),.image_lookup_slot(image_lookup_slot),.image_lookup_lba(image_lookup_lba),.image_lookup_size(image_lookup_size),.image_lookup_valid(image_lookup_valid),
    .image_types(), .image_sectors(), .image_ids(),
    .wav_present(wav_present),.wav_lba(wav_lba),.wav_size(wav_size),
    .video_wav_present(video_wav_present),.video_wav_lba(video_wav_lba),.video_wav_size(video_wav_size),
    .video_present(video_present),.video_lba(video_lba),.video_size(video_size)
);

reg              first_image_committed;
reg              auto_play_en;
assign playback_auto=auto_play_en;
reg [$clog2(CLK_FREQ_HZ)-1:0] auto_cnt;
wire [3:0]       img_found_count = index_count;
reg [3:0]        img_idx;
reg [3:0]        load_idx;
reg [1:0]        pending_buf_idx;
reg              next_req_pending;
reg              load_busy;
reg [$clog2(CLK_FREQ_HZ*5+2)-1:0] load_timeout_cnt;
reg transition_pending;
reg [1:0] transition_done_sync,transition_failed_sync;
assign transition_target_buf=pending_buf_idx[0];

reg              load_abort;

reg              source_done_seen;
reg              write_done_seen;

reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire [3:0] next_from_current;

wire composed_done,composed_failed,compositor_sector_ready,bmp_streaming;
wire [12:0] parsed_width,parsed_height;
wire parsed_dimensions,bmp_pixel_ready;
wire [8:0] fit_width,fit_height;
assign image_info_video=desired_video || display_is_video;
wire [18:0] composed_pixel_count  ;
wire bc_we,vc_we;wire[9:0]bc_wa,vc_wa,bc_ra,vc_ra;wire[23:0]bc_wd,vc_wd,source_cache_q;
media_source_line_ram u_source_lines(.clk(clk),.we(load_is_video?vc_we:bc_we),.wa(load_is_video?vc_wa:bc_wa),.wd(load_is_video?vc_wd:bc_wd),.ra(load_is_video?vc_ra:bc_ra),.q(source_cache_q));
bmp_scale_compositor #(.EXTERNAL_LINE_RAM(1)) u_scale_compositor(
 .zoom_level(load_zoom), .cache_write_en(bc_we),.cache_write_addr(bc_wa),.cache_write_data(bc_wd),.cache_read_addr(bc_ra),.cache_read_data(source_cache_q),
 .clk(clk),.rst(rst),.start(load_start_pulse),.abort(load_abort || bmp_failed || bmp_bus_error),
 .streaming(bmp_streaming),.source_done(bmp_done),.in_valid(bmp_data_wr_en),.in_rgb(bmp_data),
 .src_width(parsed_width),.src_height(parsed_height),.dimensions_valid(parsed_dimensions),.in_ready(bmp_pixel_ready),
 .fit_width(fit_width),.fit_height(fit_height),.configured(),
 .sector_ready(compositor_sector_ready),.write_ready(write_ready),.write_en(bmp_write_en),.write_data(bmp_write_data),
 .frame_done(composed_done),.failed(composed_failed),.output_count(composed_pixel_count));
assign auto_tick  = (auto_cnt == (CLK_FREQ_HZ - 1));
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
assign state_code = transport_failed ? 4'd9 : index_failed ? (index_error == 6 ? 4'd7 : 4'd6) :
                    (fatal_error || bmp_failed || composed_failed) ? 4'd8 : !index_done ? 4'd5 : wav_failed ? 4'ha : state_code_i;

generate if(EXTERNAL_KEYS)begin
 assign key_next_press=extra_next_press;assign key_auto_press=extra_auto_press;
end else begin
key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (50)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (50)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);
end endgenerate

function [3:0] next_index_limited;
 input [3:0] cur;input [3:0] count;
 begin next_index_limited=(count<=1 || cur+4'd1>=count)?4'd0:cur+4'd1;end
endfunction
function [31:0] sector_lut;
 input [3:0] idx;
 begin sector_lut=index_lbas[idx*32+:32];end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
 if(rst) begin
  current_program<=0;program_switch_pending<=0;program_to_first<=0;program_audio_token<=0;program_end_seen<=0;program_reset_count<=16;program_end_sync<=0;
  image_info_data<=0;image_info_toggle<=0;
  wrfin_tgl_sync<=0;fatal_error<=0;load_size<=0;read_active_sync<=0;
  load_start_pulse<=0;load_sector<=0;first_image_committed<=0;
  load_zoom<=1;image_zoom_applied<=1;auto_play_en<=1;auto_cnt<=0;img_idx<=0;load_idx<=0;
  pending_buf_idx<=0;write_buf_idx<=0;disp_buf_idx<=0;next_req_pending<=0;manual_next_pending<=0;
  load_busy<=0;load_timeout_cnt<=0;load_abort<=0;source_done_seen<=0;write_done_seen<=0;display_valid<=0;
  transition_pending<=0;transition_request_toggle<=0;transition_fast<=0;
  transition_done_sync<=0;transition_failed_sync<=0;
  video_restart_pending<=0;discard_standby<=0;
  desired_video<=0;display_is_video<=0;load_is_video<=0;return_needed<=0;cancel_picture<=0;
  video_write_req<=0;video_kick_pending<=0;video_frame_start<=0;video_frame_index<=0;
  video_loaded_serial<=0;video_display_serial<=0;video_display_frame<=0;first_video_arm<=0;first_video_token<=0;video_second_clock<=0;video_fps_accum<=0;video_actual_fps<=0;
  video_late_count<=0;video_missed_slots<=0;video_loop_count<=0;video_frames_displayed<=0;
 end else begin
  program_end_sync<={program_end_sync[0],program_end};
  if(program_reset_count!=0)program_reset_count<=program_reset_count-1'b1;
  if(!program_end_sync[1])program_end_seen<=0;
  if(!desired_video)begin program_switch_pending<=0;end

  if(program_end_sync[1] && desired_video && first_video_arm && !program_end_seen && program_reset_count==0 && !program_switch_pending)begin
   program_switch_pending<=1;program_to_first<=0;program_end_seen<=1;first_video_arm<=0;discard_standby<=1;
  end
  if(program_switch_pending && desired_video && !load_busy && !transition_pending && sector_owner!=4 && !video_read_req && !key_next_press && !key_auto_press && !media_skip_press)begin
   current_program<=program_to_first?2'd0:(current_program==2?2'd0:current_program+1'b1);
   program_audio_token<=~program_audio_token;program_reset_count<=16;
   video_restart_pending<=1;first_video_arm<=0;program_switch_pending<=0;
  end
  read_active_sync<={read_active_sync[0],read_active_buf};
  transition_done_sync<={transition_done_sync[0],transition_done_toggle};
  transition_failed_sync<={transition_failed_sync[0],transition_failed};
  wrfin_tgl_sync<={wrfin_tgl_sync[1:0],write_finish_toggle};
  load_start_pulse<=0;load_abort<=0;video_frame_start<=0;
  if(video_write_req && safe_write_ack) video_write_req<=0;
  if(video_kick_pending && !video_write_req && !safe_write_ack) begin
   video_kick_pending<=0;video_frame_start<=1;
  end

  if(video_second_clock==CLK_FREQ_HZ-1) begin
   video_second_clock<=0;video_actual_fps<=video_fps_accum;video_fps_accum<=0;
  end else video_second_clock<=video_second_clock+1'b1;
  if(!desired_video)first_video_arm<=0;

  if(load_busy && !transition_pending) begin
   if(!video_kick_pending && !video_frame_start && !load_start_pulse &&
      (load_is_video ? video_composed_done : (bmp_done && composed_done))) source_done_seen<=1;
   if(write_finish_pulse) write_done_seen<=1;
  end
  if(load_busy && transition_pending) begin
   load_timeout_cnt<=0;
   if(transition_done_sync[1]==transition_request_toggle) begin
    transition_pending<=0;load_busy<=0;source_done_seen<=0;write_done_seen<=0;
    if(transition_failed_sync[1]) fatal_error<=1;
    else begin
     disp_buf_idx<=pending_buf_idx;display_is_video<=load_is_video;
     if(load_is_video) begin
      video_frames_displayed<=video_frames_displayed+1'b1;

      video_fps_accum<=(video_second_clock==CLK_FREQ_HZ-1)?8'd1:video_fps_accum+1'b1;
      video_display_serial<=video_loaded_serial;video_display_frame<=video_frame_index;
      if(video_frame_index<video_display_frame && video_loaded_serial>video_display_serial)
       video_loop_count<=video_loop_count+1'b1;
     end else begin image_zoom_applied<=load_zoom;img_idx<=load_idx;return_needed<=0;image_info_data<={index_count,(load_idx+4'd1),parsed_width,parsed_height,fit_width,fit_height};image_info_toggle<=~image_info_toggle;end
    end
   end
  end else if(load_busy && source_done_seen && write_done_seen) begin
   load_timeout_cnt<=0;
   if(((load_is_video!=desired_video || discard_standby) && first_image_committed) || (!load_is_video && cancel_picture && first_image_committed && !display_is_video)) begin

    load_busy<=0;source_done_seen<=0;write_done_seen<=0;cancel_picture<=0;discard_standby<=0;
   end else if(!first_image_committed) begin
    load_busy<=0;source_done_seen<=0;write_done_seen<=0;disp_buf_idx<=pending_buf_idx;
    image_zoom_applied<=load_zoom;img_idx<=load_idx;display_valid<=1;first_image_committed<=1;display_is_video<=0;image_info_data<={index_count,(load_idx+4'd1),parsed_width,parsed_height,fit_width,fit_height};image_info_toggle<=~image_info_toggle;
   end else if(load_is_video && !video_restart_pending && display_is_video && (loaded_frame_stale || loaded_frame_deadline_risk))begin

    load_busy<=0;source_done_seen<=0;write_done_seen<=0;
    video_late_count<=video_late_count+1'b1;
    video_missed_slots<=video_missed_slots+(audio_frame_serial-video_loaded_serial);
   end else if(!load_is_video || (audio_prepared && audio_selected_video &&
               (!display_is_video || video_loaded_serial==0 || (timeline_running_sync[1] && loaded_frame_due)))) begin
    transition_request_toggle<=~transition_request_toggle;transition_pending<=1;
   end
  end else if(load_busy) begin
   if((load_is_video && video_failed) || (!load_is_video && (bmp_failed || composed_failed)) ||
       load_timeout_cnt>CLK_FREQ_HZ*5) begin
    load_busy<=0;load_timeout_cnt<=0;source_done_seen<=0;write_done_seen<=0;

    load_abort<=!load_is_video;
    video_write_req<=0;video_kick_pending<=0;
    if(load_is_video && video_failed && !transport_failed) begin
     desired_video<=0;auto_play_en<=1;return_needed<=display_is_video;
    end else fatal_error<=1;
   end else if(write_finish_pulse || (load_is_video ? (video_data_valid || video_write_en) :
       (bmp_data_valid || (bmp_data_wr_en && bmp_pixel_ready) || bmp_write_en)))load_timeout_cnt<=0;
   else load_timeout_cnt<=load_timeout_cnt+1'b1;
  end else load_timeout_cnt<=0;

  if(index_ready) begin
   if(key_next_press) begin
    if(desired_video) begin desired_video<=0;auto_play_en<=0;return_needed<=1;end
    else begin
     auto_play_en<=~auto_play_en;
     if(auto_play_en && load_busy && !load_is_video && !transition_pending) cancel_picture<=1;
    end
    auto_cnt<=0;
   end
   if(key_auto_press) begin
    manual_next_pending<=0;
    if(load_busy && !transition_pending) discard_standby<=1;
    if(desired_video) begin desired_video<=0;auto_play_en<=1;return_needed<=1;end
    else if(video_present && video_wav_present && !video_failed) begin desired_video<=1;video_restart_pending<=1;first_video_arm<=0;cancel_picture<=0;program_switch_pending<=1;program_to_first<=1;end
    auto_cnt<=0;
   end

   if(media_skip_press && !key_next_press && !key_auto_press)begin
    auto_cnt<=0;
    if(desired_video)begin
     program_switch_pending<=1;program_to_first<=0;
     first_video_arm<=0;discard_standby<=1;
    end else manual_next_pending<=1;
   end
   if(((video_failed && !video_reader_reset) || (audio_source_failed && audio_selected_video)) && desired_video) begin desired_video<=0;auto_play_en<=1;return_needed<=display_is_video;end
   if(auto_play_en && display_valid && !load_busy && !desired_video && !display_is_video && !return_needed && !media_skip_press)
    if(auto_tick) begin auto_cnt<=0;next_req_pending<=1;end else auto_cnt<=auto_cnt+1'b1;
   else auto_cnt<=0;

   if(!load_busy && !fatal_error && !key_next_press && !key_auto_press && !media_skip_press && sd_init_done && (read_active_sync[1]==disp_buf_idx[0])) begin
    if(desired_video && !program_switch_pending && !video_reader_reset && !program_end_sync[1] && first_image_committed && video_header_valid && !video_failed && audio_prepared && audio_selected_video && audio_program==current_program && (video_restart_pending || video_predict_serial<program_frames)) begin
     discard_standby<=0;
     if(video_restart_pending)begin
      video_frame_index<=0;video_loaded_serial<=0;video_restart_pending<=0;
      first_video_arm<=1;first_video_token<=~transition_request_toggle;
     end else if(video_choose_predicted)begin
      video_frame_index<=video_predict_frame;video_loaded_serial<=video_predict_serial;
     end else begin
      video_frame_index<=(video_display_frame==program_frames-1)?0:video_display_frame+1'b1;
      video_loaded_serial<=video_display_serial+1'b1;
     end

     transition_fast<=1;
     load_is_video<=1;pending_buf_idx<=next_buf_lut(disp_buf_idx,display_valid);
     write_buf_idx<=next_buf_lut(disp_buf_idx,display_valid);
     load_zoom<=zoom_sd;video_write_req<=1;video_kick_pending<=1;load_busy<=1;source_done_seen<=0;write_done_seen<=0;
    end else if((!desired_video || !first_image_committed) && bmp_ready && !bmp_failed && image_lookup_valid && image_lookup_slot==image_lookup_target &&
       (!first_image_committed || return_needed || display_is_video || ((auto_play_en && next_req_pending) || manual_next_pending || zoom_dirty))) begin
     load_zoom<=zoom_sd;load_is_video<=0;discard_standby<=0;transition_fast<=zoom_reload;
     load_idx<=(!first_image_committed)?0:((return_needed || display_is_video || zoom_reload)?img_idx:next_from_current);
     load_sector<=image_lookup_lba;
     load_size<=image_lookup_size;
     pending_buf_idx<=next_buf_lut(disp_buf_idx,display_valid);write_buf_idx<=next_buf_lut(disp_buf_idx,display_valid);
     load_start_pulse<=1;load_busy<=1;source_done_seen<=0;write_done_seen<=0;next_req_pending<=0;if(first_image_committed && !return_needed && !display_is_video)manual_next_pending<=0;cancel_picture<=0;
    end
   end
  end
 end
end

video_stream_reader #(.SRC_WIDTH(VIDEO_SRC_W),.SRC_HEIGHT(VIDEO_SRC_H),.FRAME_COUNT(VIDEO_FRAMES),.FRAME_BITS(FRAME_BITS),.PROGRAM1_FRAMES(PROGRAM1_FRAMES),.PROGRAM2_FRAMES(PROGRAM2_FRAMES),.FPS(VIDEO_FPS)) u_video_reader(
 .clk(clk),.rst(video_reader_reset),.program_select(current_program),.start(index_done && video_present && !index_failed),
 .start_lba(video_lba),.file_size(video_size),.frame_start(video_frame_start),.frame_index(video_frame_index),
 .read_req(video_read_req),.read_addr(video_addr),.read_data(sd_sec_read_data),
 .read_valid(video_data_valid),.read_end(video_read_end),.read_error(video_bus_error),
 .header_valid(video_header_valid),.failed(video_failed),.error_code(),
 .pixel_valid(video_pixel_valid),.pixel_data(video_pixel),.pixel_ready(video_pixel_ready),.frame_done(video_source_done),.busy());
video_frame_compositor #(.SRC_WIDTH(VIDEO_SRC_W),.SRC_HEIGHT(VIDEO_SRC_H),.EXTERNAL_LINE_RAM(1)) u_video_compositor(
 .zoom_level(load_zoom), .cache_write_en(vc_we),.cache_write_addr(vc_wa),.cache_write_data(vc_wd),.cache_read_addr(vc_ra),.cache_read_data(source_cache_q),
 .clk(clk),.rst(rst),.start(video_frame_start),.pixel_valid(video_pixel_valid),.pixel_data(video_pixel),
 .pixel_ready(video_pixel_ready),.source_done(video_source_done),.write_ready(write_ready),
 .write_en(video_write_en),.write_data(video_write_data),.frame_done(video_composed_done),.output_count());

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .load_start             (load_start_pulse),
    .load_abort             (load_abort || bmp_bus_error),
    .load_sector            (load_sector),
    .load_size(load_size), .load_done(bmp_done), .load_failed(bmp_failed),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code_i),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (bmp_write_req),
    .write_req_ack          (safe_write_ack),
    .sd_sec_read            (bmp_read_req),
    .sd_sec_read_addr       (bmp_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (bmp_data_valid),
    .sd_sec_read_end        (bmp_read_end),
    .pixel_sector_ready(compositor_sector_ready),.load_data_active(bmp_streaming),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data),.pixel_ready(bmp_pixel_ready),
    .source_width(parsed_width),.source_height(parsed_height),.dimensions_valid(parsed_dimensions)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (8'd0),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [(($clog2(DEBOUNCE_CYCLES)>0)?$clog2(DEBOUNCE_CYCLES):1)-1:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
