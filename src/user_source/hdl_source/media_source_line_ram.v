module media_source_line_ram(input clk,input we,input[9:0]wa,input[23:0]wd,input[9:0]ra,output reg[23:0]q);
 (*ram_style="bram_9k"*)reg[23:0]mem[0:1023];
 always @(posedge clk)begin if(we)mem[wa]<=wd;q<=mem[ra];end
endmodule
