module native_command_rom(input clk,input [5:0] address,output reg [48:0] q);
(* ram_style="bram_9k" *)reg [48:0] mem[0:63];
initial
`ifdef VERILATOR
 $readmemh("src/user_source/hdl_source/native_commands.mem",mem);
`else
 $readmemh("native_commands.mem",mem);
`endif
always @(posedge clk)q<=mem[address];
endmodule
module native_label_rom(input clk,input [10:0] address,output reg [7:0] q);
(* ram_style="bram_32k" *)reg [7:0] mem[0:2047];
initial
`ifdef VERILATOR
 $readmemh("src/user_source/hdl_source/native_labels.mem",mem);
`else
 $readmemh("native_labels.mem",mem);
`endif
always @(posedge clk)q<=mem[address];
endmodule
