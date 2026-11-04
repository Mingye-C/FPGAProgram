`timescale 1ns/1ps
module frame_fifo_read
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,
	parameter COUNT_BITS             = ADDR_BITS,
	parameter FIFO_DEPTH             = 512,
	parameter BURST_SIZE             = 128
)
(
	input [9:0] mix_config_async,
	input                            rst,
	input                            mem_clk,
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
    input							 Sdr_rd_en,
	input							 App_wr_busy,
    output							 O_rd_busy,

	output 							 App_rd_en,
	output  [ADDR_BITS - 1:0]		 App_rd_addr,

	input                            read_req,
	output reg                       read_req_ack,
    output fifo_write_en,
    output reg [1:0] read_active_buf,
	output                           read_finish,
	input[ADDR_BITS - 1:0]           read_addr_0,
	input[ADDR_BITS - 1:0]           read_addr_1,
	input[ADDR_BITS - 1:0]           read_addr_2,
	input[ADDR_BITS - 1:0]           read_addr_3,
	input[1:0]                       read_addr_index,
	input[ADDR_BITS - 1:0]           read_len,
	output reg                       fifo_aclr,
	input[9:0]                      wrusedw

);
localparam ONE                       = 256'd1;
localparam ZERO                      = 256'd0;

localparam S_IDLE                    = 0;
localparam S_ACK                     = 1;
localparam S_CHECK_FIFO              = 2;
localparam S_READ_BURST              = 3;
localparam S_READ_BURST_END          = 4;
localparam S_END                     = 5;
localparam S_PLAN = 6;
localparam S_GEOM = 7;
reg [9:0] segment_latched;reg source_latched;

reg                                  read_req_d0;
reg                                  read_req_d1;
reg                                  read_req_d2;
reg[COUNT_BITS-1:0]                 read_len_d0;
reg[COUNT_BITS-1:0]                 read_len_d1;
reg[COUNT_BITS-1:0]                 read_len_latch;
reg[COUNT_BITS-1:0]                 read_cnt;
reg[3:0]                             state;
reg[1:0]                             read_addr_index_d0;
reg[1:0]                             read_addr_index_d1;
reg [ADDR_BITS - 1:0]	 App_rd_addr_r;

reg [BURST_BITS - 1:0]				burst_cnt;
wire								rd_burst_finish;
reg App_rd_en_r;
reg App_rd_en_d0;

reg [9:0] mix_latched;reg [9:0] scan_x;reg [8:0] scan_y;
reg [8:0] burst_length;

reg [8:0] logical_length,returns_left,useful_left;
reg [1:0] skip_left;
assign fifo_write_en=Sdr_rd_en && returns_left!=0 && skip_left==0 && useful_left!=0;

wire mixing=mix_latched[9:8]!=0;
function [9:0] cut;input [5:0] n;
 reg[63:0]plane0;
 reg[63:0]plane1;
 reg[63:0]plane2;
 reg[63:0]plane3;
 reg[63:0]plane4;
 reg[63:0]plane5;
 reg[63:0]plane6;
 reg[63:0]plane7;
 reg[63:0]plane8;
 reg[63:0]plane9;
begin
 plane0=64'h0000F07C1F0F83E0;cut[0]=plane0[n];
 plane1=64'h0000552AB55AA955;cut[1]=plane1[n];
 plane2=64'h000099B3266CCD99;cut[2]=plane2[n];
 plane3=64'h00004B696D25A4B4;cut[3]=plane3[n];
 plane4=64'h0000924DB64936D9;cut[4]=plane4[n];
 plane5=64'h0000E38E3871C71E;cut[5]=plane5[n];
 plane6=64'h0000FC0FC07E07E0;cut[6]=plane6[n];
 plane7=64'hFFFF000FFF8007FF;cut[7]=plane7[n];
 plane8=64'h0000000FFFFFF800;cut[8]=plane8[n];
 plane9=64'hFFFFFFF000000000;cut[9]=plane9[n];
end endfunction
reg [2:0] cell_x,cell_y;reg [9:0] edge_x;reg select_new;
wire [5:0] tile_rank={1'b0,cell_y,2'b0}+{4'b0,cell_x[2:1]}+((cell_x[0]^cell_y[0])?6'd24:6'd0);
wire [9:0] wipe_edge=cut(mix_latched[7:2]);
always @* begin
 cell_x=0;cell_y=0;edge_x=640;select_new=0;
 if(scan_x>=211)cell_x=3'd1;
 if(scan_x>=272)cell_x=3'd2;
 if(scan_x>=333)cell_x=3'd3;
 if(scan_x>=395)cell_x=3'd4;
 if(scan_x>=456)cell_x=3'd5;
 if(scan_x>=517)cell_x=3'd6;
 if(scan_x>=578)cell_x=3'd7;
 if(scan_y>=60)cell_y=3'd1;
 if(scan_y>=120)cell_y=3'd2;
 if(scan_y>=180)cell_y=3'd3;
 if(scan_y>=240)cell_y=3'd4;
 if(scan_y>=300)cell_y=3'd5;
 if(scan_y<360)begin
  if(scan_x<150)edge_x=150;
  else if(scan_x>=640)edge_x=640;
  else if(mix_latched[9:8]==1)begin
   select_new=scan_x<wipe_edge;edge_x=select_new?wipe_edge:640;
  end else begin
   select_new=tile_rank<mix_latched[7:2];
   case(cell_x)
3'd0:edge_x=10'd211;
3'd1:edge_x=10'd272;
3'd2:edge_x=10'd333;
3'd3:edge_x=10'd395;
3'd4:edge_x=10'd456;
3'd5:edge_x=10'd517;
3'd6:edge_x=10'd578;
3'd7:edge_x=10'd640;
   endcase
  end
 end
end
wire [9:0] segment_left=segment_latched;
wire [9:0] page_left=10'd256-{2'b0,read_cnt[7:0]};
wire [9:0] available=segment_left<page_left?segment_left:page_left;
wire [8:0] planned_length=mixing?(available>128?9'd128:available[8:0]):BURST_SIZE;
wire [8:0] expanded_length=planned_length+{7'd0,read_cnt[1:0]}+9'd3;
wire [8:0] physical_length=mixing?{expanded_length[8:2],2'b00}:BURST_SIZE;
wire chosen_buf=source_latched;
wire [ADDR_BITS-1:0] mixed_address=(chosen_buf?read_addr_1:read_addr_0)+read_cnt;

wire rd_vld;
reg [3:0] rd_delay;

assign App_rd_addr = {App_rd_addr_r[ADDR_BITS - 1:0]};
assign rd_vld = (state == S_READ_BURST && burst_cnt >= burst_length);

assign O_rd_busy = (state == S_GEOM || state == S_PLAN || state == S_READ_BURST || state == S_READ_BURST_END ||
                   (state == S_CHECK_FIFO && wrusedw < (FIFO_DEPTH - logical_length)));

assign rd_burst_finish = (rd_vld && rd_delay == 4'd10 && returns_left==0);
assign read_finish = (state == S_END) ? 1'b1 : 1'b0;
assign App_rd_en = App_rd_en_d0;
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		read_req_d0    <=  1'b0;
		read_req_d1    <=  1'b0;
		read_req_d2    <=  1'b0;
		read_len_d0    <=  ZERO[ADDR_BITS - 1:0];
		read_len_d1    <=  ZERO[ADDR_BITS - 1:0];
		read_addr_index_d0 <= 2'b00;
		read_addr_index_d1 <= 2'b00;
	end
	else
	begin
		read_req_d0    <=  read_req;
		read_req_d1    <=  read_req_d0;
		read_req_d2    <=  read_req_d1;
		read_len_d0    <=  read_len;
		read_len_d1    <=  read_len_d0;
		read_addr_index_d0 <= read_addr_index;
		read_addr_index_d1 <= read_addr_index_d0;

	end
end

always @(posedge mem_clk or posedge rst)
begin
	if(rst || App_rd_en)begin
        rd_delay <= 4'd0;
    end
    else if(rd_delay < 4'd10)begin
    	rd_delay <= rd_delay + 1'b1;
    end
end
always @(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		burst_cnt <= ZERO[BURST_BITS - 1:0];
		App_rd_addr_r <= ZERO[ADDR_BITS - 1:0];
		App_rd_en_d0 <= 1'b0;
	end
	else begin

		if(state == S_CHECK_FIFO)
			burst_cnt <= ZERO[BURST_BITS - 1:0];
		else if(App_rd_en)
			burst_cnt <= burst_cnt + 1'b1;
		else
			burst_cnt <= burst_cnt;

		if(state == S_ACK)
			begin
				if(read_addr_index_d1 == 2'd0)
					App_rd_addr_r <= read_addr_0;
				else if(read_addr_index_d1 == 2'd1)
					App_rd_addr_r <= read_addr_1;
				else if(read_addr_index_d1 == 2'd2)
					App_rd_addr_r <= read_addr_2;
				else if(read_addr_index_d1 == 2'd3)
					App_rd_addr_r <= read_addr_3;
			end
		else if(state==S_PLAN && mixing)
            App_rd_addr_r <= {mixed_address[ADDR_BITS-1:2],2'b00};
        else if(App_rd_en)
			App_rd_addr_r <= App_rd_addr_r + 1'b1;
		else
			App_rd_addr_r <= App_rd_addr_r;

		if(App_rd_en_r && burst_cnt + App_rd_en < burst_length)
			App_rd_en_d0 <= 1'b1;
		else
			App_rd_en_d0 <= 1'b0;

	end
end
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		state <= S_IDLE;
        segment_latched<=0;source_latched<=0;
        mix_latched<=0;scan_x<=0;scan_y<=0;burst_length<=BURST_SIZE;logical_length<=BURST_SIZE;returns_left<=0;useful_left<=0;skip_left<=0;
        read_active_buf <= 0;
		read_len_latch <= ZERO[ADDR_BITS - 1:0];

		App_rd_en_r <= 1'b0;

		read_cnt <= ZERO[ADDR_BITS - 1:0];
		fifo_aclr <= 1'b0;

		read_req_ack <= 1'b0;
	end
	else begin
        if(Sdr_rd_en && returns_left!=0)begin
            returns_left<=returns_left-1'b1;
            if(skip_left!=0)skip_left<=skip_left-1'b1;
            else if(useful_left!=0)useful_left<=useful_left-1'b1;
        end
		case(state)

			S_IDLE:
			begin
				if(read_req_d2 == 1'b1 && Sdr_init_done)
				begin
					state <= S_ACK;
				end
				read_req_ack <= 1'b0;
			end

			S_ACK:
			begin
                read_active_buf <= read_addr_index_d1;mix_latched<=mix_config_async;scan_x<=0;scan_y<=0;
                returns_left<=0;useful_left<=0;skip_left<=0;
                if(mix_config_async[9:8]==0)begin burst_length<=BURST_SIZE;logical_length<=BURST_SIZE;end
				if(read_req_d2 == 1'b0)
				begin
					state <= mixing?S_GEOM:S_CHECK_FIFO;
					fifo_aclr <= 1'b0;
					read_req_ack <= 1'b0;
				end
				else
				begin

					read_req_ack <= 1'b1;

					fifo_aclr <= 1'b1;

					read_len_latch <= read_len_d1;
				end

				read_cnt <= ZERO[ADDR_BITS - 1:0];
			end
			S_GEOM:begin segment_latched<=edge_x-scan_x;source_latched<=select_new?mix_latched[1]:mix_latched[0];state<=S_PLAN;end
			S_PLAN:begin burst_length<=physical_length;logical_length<=planned_length;state<=S_CHECK_FIFO;end
			S_CHECK_FIFO:
			begin

				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end

				else if(wrusedw < (FIFO_DEPTH - logical_length) && ~App_wr_busy &&
                        !Sdr_busy && !Sdr_init_ref_vld)
				begin
					state <= S_READ_BURST;
                    returns_left<=burst_length;useful_left<=logical_length;skip_left<=mixing?read_cnt[1:0]:2'd0;

					App_rd_en_r <= 1'b1;
				end
			end

			S_READ_BURST:
			begin

				if(rd_burst_finish == 1'b1)
				begin
					App_rd_en_r <= 1'b0;
					state <= S_READ_BURST_END;

					read_cnt <= read_cnt + logical_length;
                    if(mixing)begin
                     if(scan_x+logical_length==640)begin scan_x<=0;scan_y<=scan_y+1'b1;end
                     else scan_x<=scan_x+logical_length;
                    end

				end
			end
			S_READ_BURST_END:
			begin

				if(Sdr_busy || Sdr_init_ref_vld || returns_left!=0)begin
                    state<=S_READ_BURST_END;
                end
                else if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end

				else if(read_cnt < read_len_latch)
				begin
					state <= mixing?S_GEOM:S_CHECK_FIFO;
				end
				else
				begin
					state <= S_END;
				end
			end
			S_END:
			begin
				state <= S_IDLE;
			end
			default:
				state <= S_IDLE;
		endcase
    end
end
endmodule
