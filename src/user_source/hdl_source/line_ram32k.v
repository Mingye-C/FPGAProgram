module line_ram32k(input wclk,input we,input [11:0] wa,input [23:0] wd,
 input rclk,input [11:0] ra,output [23:0] rd);
genvar c;
generate for(c=0;c<3;c=c+1)begin:color
`ifdef VERILATOR
 reg [7:0] m[0:4095];reg [7:0] q;
 always @(posedge wclk)if(we)m[wa]<=wd[c*8+:8];
 always @(posedge rclk)q<=m[ra];
 assign rd[c*8+:8]=q;
`else
 EG_LOGIC_BRAM #(.MODE("DP"),.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),
 .ADDR_WIDTH_A(12),.ADDR_WIDTH_B(12),.DATA_DEPTH_A(4096),.DATA_DEPTH_B(4096),
 .IMPLEMENT("32K"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL")) u_ram(
 .clka(wclk),.dia(wd[c*8+:8]),.addra(wa),.cea(we),.wea(we),.rsta(1'b0),.ocea(1'b1),.doa(),.bea(1'b1),
 .clkb(rclk),.dib(8'd0),.addrb(ra),.ceb(1'b1),.web(1'b0),.rstb(1'b0),.oceb(1'b1),.dob(rd[c*8+:8]),.beb(1'b1));
`endif
end endgenerate
endmodule
