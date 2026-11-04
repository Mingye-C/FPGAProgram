module hdmi_audio_melody(
    input wire clk,
    input wire rst,
    output reg audio_valid,
    output reg [23:0] audio_left,
    output reg [23:0] audio_right,
    output reg acr_valid,
    output wire [19:0] acr_n,
    output wire [19:0] acr_cts
);
localparam [24:0] PIXEL_HZ = 25'd25000000;
localparam [24:0] SAMPLE_HZ = 25'd48000;
reg [24:0] sample_acc;
wire [24:0] sample_sum = sample_acc + SAMPLE_HZ;
reg [31:0] phase;
reg [15:0] note_sample;
reg [5:0] note_index;
reg [14:0] acr_count;

wire phrase_end = (note_index == 6'd6)  || (note_index == 6'd13) ||
                  (note_index == 6'd20) || (note_index == 6'd27) ||
                  (note_index == 6'd34) || (note_index == 6'd41);
wire [15:0] note_length = phrase_end ? 16'd48000 : 16'd24000;

function [31:0] note_step;
    input [5:0] index;
    begin
        case (index)
            6'd0: note_step = 32'd23409859;
            6'd1: note_step = 32'd23409859;
            6'd2: note_step = 32'd35075158;
            6'd3: note_step = 32'd35075158;
            6'd4: note_step = 32'd39370534;
            6'd5: note_step = 32'd39370534;
            6'd6: note_step = 32'd35075158;
            6'd7: note_step = 32'd31248413;
            6'd8: note_step = 32'd31248413;
            6'd9: note_step = 32'd29494575;
            6'd10: note_step = 32'd29494575;
            6'd11: note_step = 32'd26276679;
            6'd12: note_step = 32'd26276679;
            6'd13: note_step = 32'd23409859;
            6'd14: note_step = 32'd35075158;
            6'd15: note_step = 32'd35075158;
            6'd16: note_step = 32'd31248413;
            6'd17: note_step = 32'd31248413;
            6'd18: note_step = 32'd29494575;
            6'd19: note_step = 32'd29494575;
            6'd20: note_step = 32'd26276679;
            6'd21: note_step = 32'd35075158;
            6'd22: note_step = 32'd35075158;
            6'd23: note_step = 32'd31248413;
            6'd24: note_step = 32'd31248413;
            6'd25: note_step = 32'd29494575;
            6'd26: note_step = 32'd29494575;
            6'd27: note_step = 32'd26276679;
            6'd28: note_step = 32'd23409859;
            6'd29: note_step = 32'd23409859;
            6'd30: note_step = 32'd35075158;
            6'd31: note_step = 32'd35075158;
            6'd32: note_step = 32'd39370534;
            6'd33: note_step = 32'd39370534;
            6'd34: note_step = 32'd35075158;
            6'd35: note_step = 32'd31248413;
            6'd36: note_step = 32'd31248413;
            6'd37: note_step = 32'd29494575;
            6'd38: note_step = 32'd29494575;
            6'd39: note_step = 32'd26276679;
            6'd40: note_step = 32'd26276679;
            6'd41: note_step = 32'd23409859;
            default: note_step = 32'd23409859;
        endcase
    end
endfunction

function [23:0] sine_sample;
    input [4:0] index;
    begin
        case (index)
            5'd0: sine_sample = 24'sd0;
            5'd1: sine_sample = 24'sd204567;
            5'd2: sine_sample = 24'sd401273;
            5'd3: sine_sample = 24'sd582558;
            5'd4: sine_sample = 24'sd741455;
            5'd5: sine_sample = 24'sd871859;
            5'd6: sine_sample = 24'sd968758;
            5'd7: sine_sample = 24'sd1028428;
            5'd8: sine_sample = 24'sd1048576;
            5'd9: sine_sample = 24'sd1028428;
            5'd10: sine_sample = 24'sd968758;
            5'd11: sine_sample = 24'sd871859;
            5'd12: sine_sample = 24'sd741455;
            5'd13: sine_sample = 24'sd582558;
            5'd14: sine_sample = 24'sd401273;
            5'd15: sine_sample = 24'sd204567;
            5'd16: sine_sample = 24'sd0;
            5'd17: sine_sample = -24'sd204567;
            5'd18: sine_sample = -24'sd401273;
            5'd19: sine_sample = -24'sd582558;
            5'd20: sine_sample = -24'sd741455;
            5'd21: sine_sample = -24'sd871859;
            5'd22: sine_sample = -24'sd968758;
            5'd23: sine_sample = -24'sd1028428;
            5'd24: sine_sample = -24'sd1048576;
            5'd25: sine_sample = -24'sd1028428;
            5'd26: sine_sample = -24'sd968758;
            5'd27: sine_sample = -24'sd871859;
            5'd28: sine_sample = -24'sd741455;
            5'd29: sine_sample = -24'sd582558;
            5'd30: sine_sample = -24'sd401273;
            5'd31: sine_sample = -24'sd204567;
            default: sine_sample = 24'd0;
        endcase
    end
endfunction

assign acr_n = 20'd6144;
assign acr_cts = 20'd25000;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sample_acc <= 25'd0;
        phase <= 32'd0;
        note_sample <= 16'd0;
        note_index <= 6'd0;
        acr_count <= 15'd0;
        audio_valid <= 1'b0;
        audio_left <= 24'd0;
        audio_right <= 24'd0;
        acr_valid <= 1'b0;
    end else begin
        audio_valid <= 1'b0;
        acr_valid <= 1'b0;

        if (acr_count == 15'd24999) begin
            acr_count <= 15'd0;
            acr_valid <= 1'b1;
        end else
            acr_count <= acr_count + 15'd1;

        if (sample_sum >= PIXEL_HZ) begin
            sample_acc <= sample_sum - PIXEL_HZ;
            audio_valid <= 1'b1;

            if (note_sample < note_length - 16'd2400) begin
                audio_left <= sine_sample(phase[31:27]);
                audio_right <= sine_sample(phase[31:27]);
            end else begin
                audio_left <= 24'd0;
                audio_right <= 24'd0;
            end
            if (note_sample == note_length - 16'd1) begin
                note_sample <= 16'd0;
                if (note_index == 6'd41)
                    note_index <= 6'd0;
                else
                    note_index <= note_index + 6'd1;
                phase <= 32'd0;
            end else begin
                note_sample <= note_sample + 16'd1;
                phase <= phase + note_step(note_index);
            end
        end else
            sample_acc <= sample_sum;
    end
end
endmodule
