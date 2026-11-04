`timescale 1ns/1ps
module frame_read_write
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter READ_DATA_BITS         = 32,
	parameter WRITE_DATA_BITS        = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,
	parameter BURST_SIZE             = 256,
	parameter WRITE_V_FLIP           = 1,
	parameter FRAME_WIDTH            = 640,
	parameter FRAME_HEIGHT           = 480
)
(
	input [9:0] mix_config_async,
	input                            rst,
	input                            mem_clk,
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,

	output							 App_rd_en,
	output[ADDR_BITS - 1:0]			 App_rd_addr,
	input							 Sdr_rd_en,
	input[MEM_DATA_BITS - 1:0]		 Sdr_rd_dout,

	input                            read_clk,
	input                            read_req,
	output read_line_ready,
	output                           read_req_ack,
    output [1:0] read_active_buf,
	output                           read_finish,
	input[ADDR_BITS - 1:0]           read_addr_0,
	input[ADDR_BITS - 1:0]           read_addr_1,
	input[ADDR_BITS - 1:0]           read_addr_2,
	input[ADDR_BITS - 1:0]           read_addr_3,
	input[1:0]                       read_addr_index,
	input[ADDR_BITS - 1:0]           read_len,
	input                            read_en,
	output[READ_DATA_BITS  - 1:0]    read_data,

	output							 App_wr_en,
	output[ADDR_BITS - 1:0]			 App_wr_addr,
	output[MEM_DATA_BITS - 1:0]	 App_wr_din,
	output[3:0]						 App_wr_dm,

	input                            write_clk,
	input                            write_req,
	output                           write_req_ack,
	output                           write_finish,
	input[ADDR_BITS - 1:0]           write_addr_0,
	input[ADDR_BITS - 1:0]           write_addr_1,
	input[ADDR_BITS - 1:0]           write_addr_2,
	input[ADDR_BITS - 1:0]           write_addr_3,
	input[1:0]                       write_addr_index,
	input[ADDR_BITS - 1:0]           write_len,
	input                            write_en,
	output write_ready,
	input[WRITE_DATA_BITS - 1:0]     write_data

);
wire[9:0] wrusedw;
wire[BURST_BITS - 1:0]                           rdusedw;

wire 								 App_rd_busy;
wire								 App_wr_busy;

wire                                 read_fifo_aclr;
wire                                 write_fifo_aclr;

wire read_fifo_we;
wire O_wr_busy;
wire O_rd_busy;

assign App_wr_busy = O_wr_busy;
assign App_rd_busy = O_rd_busy;
assign App_wr_dm = 4'b0000;

wire write_full;
wire [8:0] write_used;
reg [3:0] write_release;
always @(posedge write_clk or posedge rst or posedge write_fifo_aclr)begin
 if(rst || write_fifo_aclr)write_release<=0;
 else write_release<={write_release[2:0],1'b1};
end
assign write_ready=write_release[3] && !write_full && write_used<9'd501;

wfifo_32_32_512 write_buf
	(
	.clkr                      	(mem_clk                  ),
	.clkw                      	(write_clk                ),
	.rst                       	(write_fifo_aclr          ),
	.we                      	(write_en                 ),
	.re                      	(App_wr_en        		  ),
	.di                       	(write_data               ),
	.empty_flag                 (                         ),
	.full_flag(write_full),
	.wrusedw(write_used),
	.rdusedw                	(rdusedw                  ),
	.dout                       (App_wr_din		          )
);

frame_fifo_write
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.BURST_SIZE                 (BURST_SIZE               ),
	.WRITE_V_FLIP               (WRITE_V_FLIP             ),
	.FRAME_WIDTH                (FRAME_WIDTH              ),
	.FRAME_HEIGHT               (FRAME_HEIGHT             )
)
frame_fifo_write_m0
(
	.rst                        (rst                      ),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .Sdr_busy					(Sdr_busy),
	.App_rd_busy				(App_rd_busy),
    .O_wr_busy					(O_wr_busy),

	.App_wr_en					(App_wr_en),
    .App_wr_addr				(App_wr_addr),
	.write_req                  (write_req                ),
	.write_req_ack              (write_req_ack            ),
	.write_finish               (write_finish             ),
	.write_addr_0               (write_addr_0             ),
	.write_addr_1               (write_addr_1             ),
	.write_addr_2               (write_addr_2             ),
	.write_addr_3               (write_addr_3             ),
	.write_addr_index           (write_addr_index         ),
	.write_len                  (write_len                ),
	.fifo_aclr                  (write_fifo_aclr          ),
	.rdusedw                 	(rdusedw                  )
);

wire [9:0] read_fifo_words;
assign read_line_ready = read_fifo_words >= FRAME_WIDTH;

rfifo_32_32_512 #(.ADDR_WIDTH_W(10),.ADDR_WIDTH_R(10),.AL_FULL_NUM(1021)) read_buf
	(
	.clkr                     	(read_clk                   ),
	.clkw                     	(mem_clk                    ),
	.rst                      	(read_fifo_aclr             ),
	.we                     	(read_fifo_we       			),
	.re                     	(read_en                    ),
	.di                      	(Sdr_rd_dout                ),
	.empty_flag					(                           ),
	.full_flag					(                           ),
	.wrusedw                	(wrusedw         	  	  		 ),
	.rdusedw                	(read_fifo_words           ),
	.dout						(read_data                  )
);

frame_fifo_read
#
(
    .COUNT_BITS($clog2(FRAME_WIDTH*FRAME_HEIGHT+BURST_SIZE+1)),
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.BURST_SIZE                 (128                      ),
    .FIFO_DEPTH(1024)
)
frame_fifo_read_m0
(
    .mix_config_async(mix_config_async),
    .fifo_write_en(read_fifo_we),
	.rst                        (rst                      ),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .Sdr_busy					(Sdr_busy),
    .Sdr_rd_en					(Sdr_rd_en),
	.App_wr_busy				(App_wr_busy),
    .O_rd_busy					(O_rd_busy),

    .App_rd_en					(App_rd_en),
    .App_rd_addr				(App_rd_addr),
	.read_req                   (read_req                 ),
	.read_req_ack               (read_req_ack             ),
    .read_active_buf            (read_active_buf          ),
	.read_finish                (read_finish              ),
	.read_addr_0                (read_addr_0              ),
	.read_addr_1                (read_addr_1              ),
	.read_addr_2                (read_addr_2              ),
	.read_addr_3                (read_addr_3              ),
	.read_addr_index            (read_addr_index          ),
	.read_len                   (read_len                 ),
	.fifo_aclr                  (read_fifo_aclr           ),
	.wrusedw                	(wrusedw                  )
);

endmodule
