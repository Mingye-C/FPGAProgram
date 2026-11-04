module st7789_logo_rom(input clk,input[12:0]address,output reg[7:0]q);
(* ram_style="bram_32k" *)reg[7:0]rom[0:8191];
initial begin
`ifdef VERILATOR
 $readmemh("src/user_source/hdl_source/st7789_logo_rle.mem",rom);
`else
 $readmemh("st7789_logo_rle.mem",rom);
`endif
end
always @(posedge clk)q<=rom[address];
endmodule
