module subtitle_key_control #(
    parameter EXTERNAL_KEY=0,
    parameter integer CLK_FREQ_HZ = 25_000_000,
    parameter integer DEBOUNCE_MS = 50,
    parameter DEFAULT_ENABLE = 1'b1
)(
    input external_press,
    input clk, input rst, input key_n, input video_vs,
    output reg subtitle_enable
);
wire press_pulse;
reg requested_enable;
reg vs_prev;
generate if(EXTERNAL_KEY)begin assign press_pulse=external_press;end else begin
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) u_key3 (
    .clk(clk),.rst(rst),.button_in(key_n),.press_pulse(press_pulse)
);
end endgenerate
always @(posedge clk or posedge rst) begin
    if(rst) begin
        requested_enable<=DEFAULT_ENABLE;
        subtitle_enable<=DEFAULT_ENABLE;
        vs_prev<=0;
    end else begin
        vs_prev<=video_vs;
        if(press_pulse) requested_enable<=~requested_enable;
        if(vs_prev && !video_vs)
            subtitle_enable<=press_pulse ? ~requested_enable : requested_enable;
    end
end
endmodule
