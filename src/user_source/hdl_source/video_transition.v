module video_transition #(
    parameter integer MAX_READER_WAIT_FRAMES = 6
)(
    input clk,input rst,output reg [9:0] mix_config,
    input request_toggle_async,input target_buf_async,input fast_commit_async,
    input [1:0] read_active_buf_async,input read_ack_async,
    input frame_read_req,
    input [23:0] in_rgb,input in_de,input in_hs,input in_vs,
    output reg [23:0] out_rgb,output reg out_de,output reg out_hs,output reg out_vs,
    output reg [1:0] read_buf_select,
    output reg done_toggle,output reg transition_failed,
    output [4:0] brightness,output busy
);
localparam IDLE=0,FADE_OUT=1,WAIT_NEW=2,DRAIN_BLACK=3,FADE_IN=4,WAIT_OLD=5,FAULT=6,FAST_ARM=7,FAST_WAIT=8;
reg [3:0] state;
reg [4:0] gain;reg[1:0]fade_phase;
reg [1:0] fast_sync;
reg [1:0] request_sync,target_sync,ack_sync;reg [1:0] active0,active1;
reg vs_prev,request_latched,target_latched;reg [1:0] old_buf;
reg ack_seen,restart_seen;
reg [3:0] wait_frames;
localparam MIX_RUN=9;reg [1:0] effect_cycle;reg [5:0] step;reg check_mode,cooldown;
wire frame_tick=vs_prev && !in_vs;
assign brightness=gain;
assign busy=state!=IDLE;

function [12:0] multiply_gain;
 input [7:0] pixel;
 input [4:0] factor;
 reg [12:0] value,pair0,pair1;
 begin
  value={5'd0,pixel};
  pair0=(factor[0]?value:13'd0)+(factor[1]?(value<<1):13'd0);
  pair1=(factor[2]?(value<<2):13'd0)+(factor[3]?(value<<3):13'd0);
  multiply_gain=pair0+pair1+(factor[4]?(value<<4):13'd0);
 end
endfunction
reg [12:0] red_product,green_product,blue_product;
reg de_p0,hs_p0,vs_p0;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  red_product<=0;green_product<=0;blue_product<=0;
  de_p0<=0;hs_p0<=0;vs_p0<=0;out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;
 end else begin
  red_product<=multiply_gain(in_rgb[23:16],gain);
  green_product<=multiply_gain(in_rgb[15:8],gain);
  blue_product<=multiply_gain(in_rgb[7:0],gain);
  de_p0<=in_de;hs_p0<=in_hs;vs_p0<=in_vs;
  out_rgb<={red_product[11:4],green_product[11:4],blue_product[11:4]};
  out_de<=de_p0;out_hs<=hs_p0;out_vs<=vs_p0;
 end
end

always @(posedge clk or posedge rst) begin
 if(rst) begin
  fast_sync<=0;request_sync<=0;target_sync<=0;active0<=0;active1<=0;ack_sync<=0;vs_prev<=0;
  mix_config<=0;effect_cycle<=0;step<=0;check_mode<=0;cooldown<=0;state<=IDLE;gain<=16;fade_phase<=0;read_buf_select<=0;done_toggle<=0;transition_failed<=0;
  request_latched<=0;target_latched<=0;old_buf<=0;
  ack_seen<=0;restart_seen<=0;wait_frames<=0;
 end else begin
  fast_sync<={fast_sync[0],fast_commit_async};
  request_sync<={request_sync[0],request_toggle_async};
  target_sync<={target_sync[0],target_buf_async};
  active0<=read_active_buf_async;active1<=active0;
  ack_sync<={ack_sync[0],read_ack_async};
  vs_prev<=in_vs;
  case(state)
  IDLE: if(request_sync[1]!=done_toggle) begin
   request_latched<=request_sync[1];target_latched<=target_sync[1];
   old_buf<=read_buf_select;transition_failed<=0;
   if(target_sync[1]==read_buf_select) done_toggle<=request_sync[1];
   else if(fast_sync[1]) state<=FAST_ARM;
   else begin
    if(effect_cycle==2)effect_cycle<=0;else effect_cycle<=effect_cycle+1'b1;
    if(effect_cycle==0)begin state<=FADE_OUT;fade_phase<=0;end
    else begin check_mode<=effect_cycle==2;step<=0;cooldown<=0;state<=MIX_RUN;end
   end
  end

  FAST_ARM: if(frame_tick) begin
   read_buf_select<=target_latched;ack_seen<=0;restart_seen<=0;wait_frames<=0;state<=FAST_WAIT;
  end
  FAST_WAIT: begin
   if(ack_sync[1] && active1==target_latched) ack_seen<=1;
   if(ack_seen && !ack_sync[1] && !frame_read_req && active1==target_latched) begin
    done_toggle<=request_latched;state<=IDLE;
   end else if(frame_tick) begin
    if(wait_frames>=MAX_READER_WAIT_FRAMES-1) begin
     transition_failed<=1;gain<=0;read_buf_select<=old_buf;
     ack_seen<=0;restart_seen<=0;wait_frames<=0;state<=WAIT_OLD;
    end else wait_frames<=wait_frames+1'b1;
   end
  end
  FADE_OUT: if(frame_tick) begin
   if(fade_phase!=2)fade_phase<=fade_phase+1'b1;else begin fade_phase<=0;
   if(gain>1) gain<=gain-1'b1;
   else begin
    gain<=0;read_buf_select<=target_latched;
    ack_seen<=0;restart_seen<=0;wait_frames<=0;state<=WAIT_NEW;
   end
  end
  end
  WAIT_NEW,WAIT_OLD: begin

   if(ack_sync[1] && active1==read_buf_select) ack_seen<=1;
   if(ack_seen && !ack_sync[1] && !frame_read_req && active1==read_buf_select)
    restart_seen<=1;
   if(frame_tick) begin
    if(restart_seen && active1==read_buf_select) begin
     state<=DRAIN_BLACK;wait_frames<=0;
    end else if(wait_frames>=MAX_READER_WAIT_FRAMES-1) begin
     transition_failed<=1;ack_seen<=0;restart_seen<=0;wait_frames<=0;
     if(state==WAIT_NEW) begin

      read_buf_select<=old_buf;state<=WAIT_OLD;
     end else begin

      done_toggle<=request_latched;state<=FAULT;
     end
    end else wait_frames<=wait_frames+1'b1;
   end
  end
  DRAIN_BLACK: if(frame_tick) begin
   if(active1==read_buf_select) begin gain<=1;fade_phase<=0;state<=FADE_IN;end
   else begin ack_seen<=0;restart_seen<=0;wait_frames<=0;state<=WAIT_OLD;transition_failed<=1;read_buf_select<=old_buf;end
  end
  FADE_IN: if(frame_tick) begin
   if(fade_phase!=2)fade_phase<=fade_phase+1'b1;else begin fade_phase<=0;
   if(gain<15) gain<=gain+1'b1;
   else begin gain<=16;done_toggle<=request_latched;state<=IDLE;end
  end
  end
  MIX_RUN:if(frame_tick)begin
   if(step==48)begin mix_config<=0;read_buf_select<={1'b0,target_latched};ack_seen<=0;wait_frames<=0;state<=FAST_WAIT;end
   else if(check_mode && step!=0 && step[1:0]==0 && !cooldown)cooldown<=1;
   else begin
    cooldown<=0;step<=step+1'b1;
    mix_config<={(check_mode?2'd2:2'd1),(step+6'd1),target_latched,old_buf[0]};
   end
  end
  FAULT: gain<=0;
  default:begin state<=FAULT;gain<=0;transition_failed<=1;done_toggle<=request_latched;end
  endcase
 end
end
endmodule
