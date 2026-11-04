module native_font_rom(input clk,input [7:0] code,input [4:0] row,col,output [1:0] ink,shadow);
(* ram_style="bram_32k" *) reg [7:0] en[0:8191];
(* ram_style="bram_32k" *) reg [7:0] cn[0:16383];
(* ram_style="bram_32k" *) reg[7:0] notice[0:4095];
initial begin
`ifdef VERILATOR
 $readmemh("src/user_source/hdl_source/native_notice_packed.mem",notice);
 $readmemh("src/user_source/hdl_source/native_ascii_packed.mem",en);
 $readmemh("src/user_source/hdl_source/native_chinese_packed.mem",cn);
`else
 $readmemh("native_notice_packed.mem",notice);
 $readmemh("native_ascii_packed.mem",en);
 $readmemh("native_chinese_packed.mem",cn);
`endif
end
wire [5:0] ec=code==8'd120 ? 6'd56:code[5:0]-6'd32;
wire [4:0] sr=row-1'b1,sc=col-1'b1;
wire [14:0] ea={ec,row,col[3:0]},es={ec,sr,sc[3:0]};
wire [15:0] ca={code[5:0],row,col},cs={code[5:0],sr,sc};
reg [7:0] eq,cq,esq,csq,nq,nsq;reg extra;reg choose,sv;reg [1:0] offset,soffset;
always @(posedge clk)begin
 eq<=en[ea[14:2]];esq<=en[es[14:2]];cq<=cn[ca[15:2]];csq<=cn[cs[15:2]];
 nq<=notice[{code[3:0],row,col[4:2]}];nsq<=notice[{code[3:0],sr,sc[4:2]}];extra<=code[6];
 choose<=code[7];sv<=row!=0 && col!=0;offset<=col[1:0];soffset<=sc[1:0];
end
reg [7:0] q,sq;reg [1:0] oq,osq;reg svq;
always @(posedge clk)begin q<=choose?(extra?nq:cq):eq;sq<=choose?(extra?nsq:csq):esq;oq<=offset;osq<=soffset;svq<=sv;end
assign ink=q[{oq,1'b0}+:2];assign shadow=svq?sq[{osq,1'b0}+:2]:2'd0;
endmodule

module native_eco_title_rom(input clk,input [10:0] x,input [9:0] y,output [1:0] ink,shadow);
(* ram_style="bram_32k" *)reg [7:0] rom[0:4095];
initial begin
`ifdef VERILATOR
 $readmemh("src/user_source/hdl_source/native_eco_title_packed.mem",rom);
`else
 $readmemh("native_eco_title_packed.mem",rom);
`endif
end
wire [7:0] tx=x-11'd22,sx=tx-1'b1;wire [5:0] ty=y-10'd548,sy=ty-1'b1;
reg [7:0] q,sq,qq,sqq;reg [1:0] off,soff,offq,soffq;reg sv,svq;
always @(posedge clk)begin
 q<=rom[{ty,tx[7:2]}];sq<=rom[{sy,sx[7:2]}];off<=tx[1:0];soff<=sx[1:0];sv<=tx!=0&&ty!=0;
 qq<=q;sqq<=sq;offq<=off;soffq<=soff;svq<=sv;
end
assign ink=qq[{offq,1'b0}+:2];assign shadow=svq?sqq[{soffq,1'b0}+:2]:2'd0;
endmodule
