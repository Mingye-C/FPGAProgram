module fft1024_serial(
 input wire clk,input wire rst,input wire sample_valid,input wire signed [15:0] sample,
 output reg bin_valid,output reg [9:0] bin_index,
 output reg signed [15:0] bin_re,bin_im,output reg block_done,output wire busy,
 output reg [31:0] capture_overrun_count,output reg [31:0] overflow_count,
 output reg [31:0] compute_cycles
);
 localparam IDLE=0,SET_A=1,GET_A=2,SET_B=3,GET_B=4,
 M0=5,M1=6,M2=7,M3=8,M4=9,M5=10,ROT=11,ADD=12,
 WRITE_A=13,WRITE_B=14,NEXT=15,OUT_SET=16,OUT_GET=17,FIN=18;
 reg [4:0] state;
 reg capture_bank,fft_bank; reg [1:0] ready;
 reg [9:0] capture_n,base,j,half_size,out_n;
 reg [3:0] stage;
 wire [9:0] addr_a=base+j,addr_b=base+j+half_size;
 wire [8:0] tw_addr=j << (9-stage);
 wire [9:0] rd_addr=(state==OUT_SET || state==OUT_GET)?out_n:
                         ((state==SET_B || state==GET_B)?addr_b:addr_a);
 wire [15:0] hann_q; wire [31:0] tw_q;
 fft_hann_rom u_hann(clk,capture_n,hann_q);
 fft_twiddle_rom u_twiddle(clk,tw_addr,tw_q);
 function [9:0] bitreverse; input [9:0] a; integer k; begin
  for(k=0;k<10;k=k+1) bitreverse[k]=a[9-k]; end endfunction
 function [15:0] sat16; input signed [18:0] v; begin
  if(v>32767) sat16=16'h7fff; else if(v < -32768) sat16=16'h8000; else sat16=v[15:0];
 end endfunction
 reg v0,v1,bank0,bank1; reg [9:0] capaddr0,capaddr1;
 reg signed [15:0] sample_q;
 reg signed [31:0] window_product;
 wire signed [31:0] window_round=(window_product+32'sd16384) >>>15;
 wire cap_write=v1;

 always @(posedge clk) begin
  window_product <= sample_q * $signed(hann_q);
 end
 (* ram_style="block" *) reg [31:0] ram0[0:1023];
 (* ram_style="block" *) reg [31:0] ram1[0:1023];
 reg [31:0] q0,q1;
 reg signed [15:0] ar,ai,br,bi,wr,wi;
 reg signed [15:0] mul_a,mul_b;
 reg signed [31:0] mul_p,p0,p1,p2,p3;
 reg signed [17:0] tr,ti;
 wire signed [32:0] rot_r=$signed({p0[31],p0})-$signed({p1[31],p1});
 wire signed [32:0] rot_i=$signed({p2[31],p2})+$signed({p3[31],p3});
 wire signed [18:0] ar_ext={{3{ar[15]}},ar},ai_ext={{3{ai[15]}},ai};
 wire signed [18:0] tr_ext={tr[17],tr},ti_ext={ti[17],ti};
 wire signed [18:0] ya_r=(ar_ext+tr_ext)>>>1,ya_i=(ai_ext+ti_ext)>>>1;
 wire signed [18:0] yb_r=(ar_ext-tr_ext)>>>1,yb_i=(ai_ext-ti_ext)>>>1;
 reg [31:0] ya,yb;
 wire fft_write=(state==WRITE_A || state==WRITE_B);
 wire [9:0] wr_addr=(state==WRITE_A)?addr_a:addr_b;
 wire [31:0] wr_data=(state==WRITE_A)?ya:yb;
 wire [31:0] fft_q=fft_bank?q1:q0;

 always @(posedge clk) begin
  q0<=ram0[rd_addr]; q1<=ram1[rd_addr];
  if(cap_write && !bank1) ram0[capaddr1]<={window_round[15:0],16'b0};
  else if(fft_write && !fft_bank) ram0[wr_addr]<=wr_data;
  if(cap_write && bank1) ram1[capaddr1]<={window_round[15:0],16'b0};
  else if(fft_write && fft_bank) ram1[wr_addr]<=wr_data;
  mul_p<=mul_a*mul_b;
 end
 assign busy=(state!=IDLE);
 reg [31:0] cycle_count;
 always @(posedge clk) begin
  if(rst) begin
   state<=IDLE;capture_bank<=0;fft_bank<=0;ready<=0;capture_n<=0;
   v0<=0;v1<=0;bank0<=0;bank1<=0;capaddr0<=0;capaddr1<=0;sample_q<=0;
   bin_valid<=0;bin_index<=0;bin_re<=0;bin_im<=0;block_done<=0;
   capture_overrun_count<=0;overflow_count<=0;compute_cycles<=0;cycle_count<=0;
   stage<=0;base<=0;j<=0;half_size<=1;out_n<=0;
   ar<=0;ai<=0;br<=0;bi<=0;wr<=0;wi<=0;mul_a<=0;mul_b<=0;
   p0<=0;p1<=0;p2<=0;p3<=0;tr<=0;ti<=0;ya<=0;yb<=0;
  end else begin
   bin_valid<=0;block_done<=0;v0<=0;v1<=v0;
   capaddr1<=capaddr0;bank1<=bank0;
   if(sample_valid) begin
    if(!ready[capture_bank]) begin
     sample_q<=sample;capaddr0<=bitreverse(capture_n);bank0<=capture_bank;v0<=1;
     capture_n<=capture_n+1'b1;
    end else capture_overrun_count<=capture_overrun_count+1'b1;
   end

   if(cap_write && capaddr1==1023) begin ready[bank1]<=1;capture_bank<=~bank1; end
   if(state!=IDLE) cycle_count<=cycle_count+1'b1;
   case(state)
    IDLE: if(ready[fft_bank]) begin stage<=0;base<=0;j<=0;half_size<=1;cycle_count<=0;state<=SET_A;end
    SET_A: state<=GET_A;
    GET_A: begin ar<=fft_q[31:16];ai<=fft_q[15:0];state<=SET_B;end
    SET_B: state<=GET_B;
    GET_B: begin br<=fft_q[31:16];bi<=fft_q[15:0];wr<=tw_q[31:16];wi<=tw_q[15:0];state<=M0;end
    M0:begin mul_a<=br;mul_b<=wr;state<=M1;end
    M1:begin mul_a<=bi;mul_b<=wi;state<=M2;end
    M2:begin mul_a<=br;mul_b<=wi;p0<=mul_p;state<=M3;end
    M3:begin mul_a<=bi;mul_b<=wr;p1<=mul_p;state<=M4;end
    M4:begin p2<=mul_p;state<=M5;end
    M5:begin p3<=mul_p;state<=ROT;end
    ROT:begin tr<=(rot_r+33'sd16384)>>>15;ti<=(rot_i+33'sd16384)>>>15;state<=ADD;end
    ADD:begin
     ya<={sat16(ya_r),sat16(ya_i)};yb<={sat16(yb_r),sat16(yb_i)};
     overflow_count<=overflow_count+
      ((ya_r>32767 || ya_r< -32768)?32'd1:32'd0)+((ya_i>32767 || ya_i< -32768)?32'd1:32'd0)+
      ((yb_r>32767 || yb_r< -32768)?32'd1:32'd0)+((yb_i>32767 || yb_i< -32768)?32'd1:32'd0);
     state<=WRITE_A;end
    WRITE_A:state<=WRITE_B;
    WRITE_B:state<=NEXT;
    NEXT:begin
     if(j!=half_size-1'b1) begin j<=j+1'b1;state<=SET_A;end
     else if({1'b0,base}+({1'b0,half_size}<<1)<1024) begin
      base<=base+(half_size<<1);j<=0;state<=SET_A;end
     else if(stage!=9) begin stage<=stage+1'b1;half_size<=half_size<<1;base<=0;j<=0;state<=SET_A;end
     else begin out_n<=0;state<=OUT_SET;end
    end
    OUT_SET:state<=OUT_GET;
    OUT_GET:begin
     bin_valid<=1;bin_index<=out_n;bin_re<=fft_q[31:16];bin_im<=fft_q[15:0];
     if(out_n==1023) state<=FIN;else begin out_n<=out_n+1'b1;state<=OUT_SET;end
    end
    FIN:begin ready[fft_bank]<=0;fft_bank<=~fft_bank;block_done<=1;compute_cycles<=cycle_count+1'b1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
