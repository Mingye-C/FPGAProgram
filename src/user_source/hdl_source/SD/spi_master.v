module spi_master
(
	input stream_read,
	input                       sys_clk,
	input                       rst,
	output                      nCS,
	output                      DCLK,
	output                      MOSI,
	input                       MISO,
	input                       CPOL,
	input                       CPHA,
	input                       nCS_ctrl,
	input[15:0]                 clk_div,
	input                       wr_req,
	output                      wr_ack,
	input[7:0]                  data_in,
	output[7:0]                 data_out
);

wire fast_half_cycle = (clk_div == 16'hffff);
localparam                   IDLE            = 0;
localparam                   DCLK_EDGE       = 1;
localparam                   DCLK_IDLE       = 2;
localparam                   ACK             = 3;
localparam                   LAST_HALF_CYCLE = 4;
localparam                   ACK_WAIT        = 5;
reg                          DCLK_reg;
reg[7:0]                     MOSI_shift;
reg[7:0]                     MISO_shift;
reg[2:0]                     state;
reg[2:0]                     next_state;
reg [15:0]                   clk_cnt;
reg[4:0]                     clk_edge_cnt;
assign MOSI = MOSI_shift[7];
assign DCLK = DCLK_reg;
assign data_out = MISO_shift;
assign wr_ack = (state == ACK);
assign nCS = nCS_ctrl;
always@(posedge sys_clk or posedge rst)
begin
	if(rst)
		state <= IDLE;
	else
		state <= next_state;
end

always@(*)
begin
	case(state)
		IDLE:
			if(wr_req == 1'b1)
				next_state <= fast_half_cycle ? DCLK_EDGE : DCLK_IDLE;
			else
				next_state <= IDLE;
		DCLK_IDLE:

			if(clk_cnt == clk_div)
				next_state <= DCLK_EDGE;
			else
				next_state <= DCLK_IDLE;
		DCLK_EDGE:

			if(clk_edge_cnt == 5'd15)
				next_state <= fast_half_cycle && stream_read ? ACK : LAST_HALF_CYCLE;
			else
				next_state <= fast_half_cycle ? DCLK_EDGE : DCLK_IDLE;

		LAST_HALF_CYCLE:
			if(fast_half_cycle || clk_cnt == clk_div)
				next_state <= ACK;
			else
				next_state <= LAST_HALF_CYCLE;

		ACK:
			next_state <= fast_half_cycle && stream_read ? DCLK_EDGE : ACK_WAIT;

		ACK_WAIT:
			next_state <= IDLE;
		default:
			next_state <= IDLE;
	endcase
end

always@(posedge sys_clk or posedge rst)
begin
	if(rst)
		DCLK_reg <= 1'b0;
	else if(state == IDLE)
		DCLK_reg <= CPOL;
	else if(state == DCLK_EDGE)
		DCLK_reg <= ~DCLK_reg;
end

always@(posedge sys_clk or posedge rst)
begin
	if(rst)
		clk_cnt <= 16'd0;
	else if(state == DCLK_IDLE || state == LAST_HALF_CYCLE)
		clk_cnt <= clk_cnt + 16'd1;
	else
		clk_cnt <= 16'd0;
end

always@(posedge sys_clk or posedge rst)
begin
	if(rst)
		clk_edge_cnt <= 5'd0;
	else if(state == DCLK_EDGE)
		clk_edge_cnt <= clk_edge_cnt + 5'd1;
	else if(state == IDLE || (state==ACK && fast_half_cycle && stream_read))
		clk_edge_cnt <= 5'd0;
end

always@(posedge sys_clk or posedge rst)
begin
	if(rst)
		MOSI_shift <= 8'd0;
	else if(state==ACK && fast_half_cycle && stream_read)
		MOSI_shift<=8'hff;
	else if(state == IDLE && wr_req)
		MOSI_shift <= data_in;
	else if(state == DCLK_EDGE)
		if(CPHA == 1'b0 && clk_edge_cnt[0] == 1'b1)
			MOSI_shift <= {MOSI_shift[6:0],MOSI_shift[7]};
		else if(CPHA == 1'b1 && (clk_edge_cnt != 5'd0 && clk_edge_cnt[0] == 1'b0))
			MOSI_shift <= {MOSI_shift[6:0],MOSI_shift[7]};
end

always@(posedge sys_clk or posedge rst)
begin
	if(rst)
		MISO_shift <= 8'd0;
	else if((state == IDLE && wr_req) || (state==ACK && fast_half_cycle && stream_read))
		MISO_shift <= 8'h00;
	else if(state == DCLK_EDGE)
		if(CPHA == 1'b0 && clk_edge_cnt[0] == 1'b0)
			MISO_shift <= {MISO_shift[6:0],MISO};
		else if(CPHA == 1'b1 && (clk_edge_cnt[0] == 1'b1))
			MISO_shift <= {MISO_shift[6:0],MISO};
end
endmodule
