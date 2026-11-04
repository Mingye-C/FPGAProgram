module audio_source_control #(
 parameter integer PCM0_BYTES=3824000,PCM1_BYTES=3104000,PCM2_BYTES=2848000,
 parameter integer PREFILL_FRAMES=2048, parameter integer EXPECTED_PCM_BYTES=2304000
)(
 input clk,input rst,input index_ready,input desired_video,input[1:0] desired_program,input restart_toggle,output reg[1:0] selected_program,
 input background_present,input soundtrack_present,
 input [2:0] sector_owner,input hdmi_quiescent_async,
 input header_valid,input reader_failed,input transport_failed,
 input [31:0] data_length,input [11:0] fifo_used,
 output reg selected_video,output reader_reset,output fifo_reset,
 output reader_start,output allow_request,output prepared,
 output failed,output session_reset
);
 localparam WAIT_INDEX=0,MUTE=1,DRAIN=2,FLUSH=3,START=4,PREFILL=5,READY=6,ERROR=7;
 reg [2:0] state;
 reg [4:0] reset_count;
 reg [1:0] mute_sync;
 reg accepted_restart;
 wire source_matches=selected_video==desired_video && (!desired_video || (selected_program==desired_program && accepted_restart==restart_toggle));
 wire[31:0] expected_bytes=selected_program==0?PCM0_BYTES:selected_program==1?PCM1_BYTES:PCM2_BYTES;
 wire present=selected_video ? soundtrack_present : background_present;
 assign reader_reset=rst || state==WAIT_INDEX || state==FLUSH;
 assign fifo_reset=reader_reset;
 assign session_reset=reader_reset;
 assign reader_start=state==START;
 assign allow_request=(state==START || state==PREFILL || state==READY) && source_matches && !transport_failed;
 assign prepared=state==READY && source_matches && !reader_failed && !transport_failed;
 assign failed=state==ERROR;
 always @(posedge clk or posedge rst) begin
  if(rst)begin state<=WAIT_INDEX;selected_program<=0;accepted_restart<=0;selected_video<=0;reset_count<=0;mute_sync<=0;end
  else begin
   mute_sync<={mute_sync[0],hdmi_quiescent_async};
   case(state)
    WAIT_INDEX:if(index_ready)state<=MUTE;
    MUTE:if(mute_sync[1])state<=DRAIN;
    DRAIN:if(sector_owner!=3'd2)begin state<=FLUSH;reset_count<=0;end
    FLUSH:if(reset_count==15)begin
     selected_video<=desired_video;selected_program<=desired_program;accepted_restart<=restart_toggle;state<=START;
    end else reset_count<=reset_count+1'b1;
    START:if(!source_matches)state<=MUTE;
          else if(!present)state<=ERROR;else state<=PREFILL;
    PREFILL:if(!source_matches)state<=MUTE;
      else if(reader_failed || transport_failed || (header_valid && selected_video && data_length!=expected_bytes))state<=ERROR;
      else if(header_valid && fifo_used>=PREFILL_FRAMES)state<=READY;
    READY:if(!source_matches)state<=MUTE;
      else if(reader_failed || transport_failed)state<=ERROR;
    ERROR:if(!source_matches)state<=MUTE;
    default:state<=WAIT_INDEX;
   endcase
  end
 end
endmodule
