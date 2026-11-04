module sidebar_logo_rom(input clk,rst,enable,in_de,input[10:0]x,input[9:0]y,output reg valid,output[23:0]rgb);
(*ram_style="bram_32k"*)reg[7:0]mem[0:8191];
initial begin
`ifdef VERILATOR
$readmemh("src/user_source/hdl_source/sidebar_logo.mem",mem);
`else
$readmemh("sidebar_logo.mem",mem);
`endif
end
wire[10:0]lx=x-11'd53;wire[9:0]ly=y-10'd32;
reg[7:0]q;reg odd;wire[3:0]index=odd?q[7:4]:q[3:0];reg[23:0]pixel;
always @(posedge clk)begin q<=mem[{ly[5:0],lx[7:1]}];odd<=lx[0];valid<=!rst&&enable&&in_de&&lx<192&&ly<64;end
always @*case(index)
4'd0:pixel=24'h102642;
4'd1:pixel=24'h20344f;
4'd2:pixel=24'h30435b;
4'd3:pixel=24'h405168;
4'd4:pixel=24'h506074;
4'd5:pixel=24'h606e81;
4'd6:pixel=24'h707d8e;
4'd7:pixel=24'h808b9a;
4'd8:pixel=24'h8f9aa7;
4'd9:pixel=24'h9fa8b3;
4'd10:pixel=24'hafb7c0;
4'd11:pixel=24'hbfc5cd;
4'd12:pixel=24'hcfd4d9;
4'd13:pixel=24'hdfe2e6;
4'd14:pixel=24'heff1f2;
4'd15:pixel=24'hffffff;
endcase
assign rgb=pixel;
endmodule
