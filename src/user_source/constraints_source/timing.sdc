

create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

derive_clocks

rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]



set_max_delay -from [get_regs {u_scaler/wg[*]}] -to [get_regs {u_scaler/wg1*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_scaler/rg[*]}] -to [get_regs {u_scaler/rg1*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_scaler/frame_toggle*}] -to [get_regs {u_source_scan/frame_sync*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_audio_cdc/req}] -to [get_regs {u_audio_cdc/req_sync*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_audio_cdc/ack}] -to [get_regs {u_audio_cdc/ack_sync*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_audio_cdc/held*}] -to [get_regs {u_audio_cdc/left* u_audio_cdc/right*}] -datapath_only 13.000
set_max_delay -from [get_clocks {clk}] -to [get_regs {system_reset_sync*}] -datapath_only 13.000

set_max_delay -from [get_regs {u_ui_state/req}] -to [get_regs {u_ui_state/req_sync*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_ui_state/ack}] -to [get_regs {u_ui_state/ack_sync*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_ui_state/held*}] -to [get_regs {u_ui_state/pending*}] -datapath_only 13.000

set_max_delay -from [get_regs {u_dht11/update_toggle*}] -to [get_regs {u_dht_state/sync*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_dht11/bcd* u_dht11/valid*}] -to [get_regs {u_dht_state/active*}] -datapath_only 13.000

set_max_delay -from [get_regs {u_dht_state/seen*}] -to [get_regs {u_dht11/ack_sync*}] -datapath_only 13.000

set_max_delay -from [get_regs {u_direction_voice/wg*}] -to [get_regs {u_direction_voice/ws0*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_direction_voice/rg*}] -to [get_regs {u_direction_voice/rs0*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_direction_voice/request}] -to [get_regs {u_direction_voice/req_sync*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_direction_voice/command_up}] -to [get_regs {u_direction_voice/lba* u_direction_voice/left*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_direction_voice/armed}] -to [get_regs {u_direction_voice/arm_sync*}] -datapath_only 13.000
set_max_delay -from [get_regs {u_direction_voice/error_flag}] -to [get_regs {u_direction_voice/error_sync*}] -datapath_only 13.000
