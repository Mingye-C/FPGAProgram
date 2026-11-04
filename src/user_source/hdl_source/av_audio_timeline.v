module av_audio_timeline #(parameter integer FRAME_COUNT=239, parameter integer PROGRAM1_FRAMES=194,PROGRAM2_FRAMES=178,SAMPLES_PER_FRAME=4000,parameter integer FRAME_BITS=$clog2(FRAME_COUNT), parameter integer SERIAL_BITS=32, parameter integer POSITION_BITS=$clog2(FRAME_COUNT*SAMPLES_PER_FRAME))(
 input clk,input rst,input [1:0] program_select_async,output reg program_end,input session_reset_async,input prepared_async,
 input selected_video_async,input first_arm_async,input first_token_async,
 input first_commit_toggle,input pcm_consume,input snapshot_ack_async,
 output play_enable,output reg running,
 output reg snapshot_req,output reg [31:0] snapshot_serial,
 output reg [FRAME_BITS-1:0] snapshot_frame,
 (* keep="true" *) output reg [31:0] loop_count,
 (* keep="true" *) output reg [POSITION_BITS-1:0] sample_position
);
 reg [3:0] program_sync;reg[1:0] program_latched;
 wire[FRAME_BITS-1:0] selected_frames=program_latched==0?FRAME_COUNT:program_latched==1?PROGRAM1_FRAMES:PROGRAM2_FRAMES;
 wire[POSITION_BITS-1:0] selected_samples=program_latched==0?FRAME_COUNT*SAMPLES_PER_FRAME:program_latched==1?PROGRAM1_FRAMES*SAMPLES_PER_FRAME:PROGRAM2_FRAMES*SAMPLES_PER_FRAME;
 reg [1:0] reset_sync,ready_sync,video_sync,arm_sync,token_sync,ack_sync;
 reg [$clog2(SAMPLES_PER_FRAME)-1:0] frame_samples;
 reg [FRAME_BITS-1:0] frame_index;
 reg [SERIAL_BITS-1:0] frame_serial;
 reg publish_pending;
 assign play_enable=ready_sync[1] && !reset_sync[1] && !program_end && (!video_sync[1] || running);
 always @(posedge clk or posedge rst) begin
  if(rst)begin
   program_sync<=0;program_latched<=0;program_end<=0;reset_sync<=3;ready_sync<=0;video_sync<=0;arm_sync<=0;token_sync<=0;ack_sync<=0;
   running<=0;frame_samples<=0;frame_index<=0;frame_serial<=0;loop_count<=0;sample_position<=0;
   snapshot_req<=0;snapshot_serial<=0;snapshot_frame<=0;publish_pending<=1;
  end else begin
   program_sync<={program_sync[1:0],program_select_async};reset_sync<={reset_sync[0],session_reset_async};ready_sync<={ready_sync[0],prepared_async};
   video_sync<={video_sync[0],selected_video_async};arm_sync<={arm_sync[0],first_arm_async};
   token_sync<={token_sync[0],first_token_async};ack_sync<={ack_sync[0],snapshot_ack_async};
   if(reset_sync[1])begin
    program_end<=0;
    running<=0;frame_samples<=0;frame_index<=0;frame_serial<=0;loop_count<=0;sample_position<=0;

    publish_pending<=1;
   end else begin
    if(!video_sync[1] || !arm_sync[1])running<=0;
    else if(!running && !program_end && ready_sync[1] && first_commit_toggle==token_sync[1])begin
     running<=1;program_latched<=program_sync[3:2];publish_pending<=1;
    end
    if(pcm_consume && video_sync[1])begin
     if(sample_position==selected_samples-1)begin sample_position<=0;loop_count<=loop_count+1'b1;program_end<=1;running<=0;end
     else sample_position<=sample_position+1'b1;
     if(frame_samples==SAMPLES_PER_FRAME-1)begin
      frame_samples<=0;frame_serial<=frame_serial+1'b1;publish_pending<=1;
      if(frame_index==selected_frames-1)frame_index<=0;else frame_index<=frame_index+1'b1;
     end else frame_samples<=frame_samples+1'b1;
    end
    if(publish_pending && snapshot_req==ack_sync[1])begin
     snapshot_serial<=frame_serial;snapshot_frame<=frame_index;
     snapshot_req<=~snapshot_req;

     publish_pending<=pcm_consume && video_sync[1] && frame_samples==SAMPLES_PER_FRAME-1;
    end
   end
  end
 end
endmodule
