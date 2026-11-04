module direction_voice(input sclk,srst,input aclk,arst,input direction_up,input[1:0]scene,input eco,
 input in_valid,input[23:0]in_left,in_right,output reg out_valid,output reg[23:0]out_left,out_right,
 output read_req,output[31:0]read_addr,input[7:0]read_data,input read_valid,read_end,read_error,
 (*preserve="true",keep="true"*)output reg[7:0]underflows);
 localparam UP_LBA=480001,DOWN_LBA=480066,UP_SAMPLES=16528,DOWN_SAMPLES=17321;
 (*ram_style="block"*)reg[15:0]mem[0:511];
 reg[9:0]wp,rp;(*preserve="true",keep="true"*)reg[9:0]wg,rg;
 (*async_reg="true",preserve="true",keep="true"*)reg[9:0]rs0,rs1,ws0,ws1;
 function[9:0]binary;input[9:0]g;integer j;begin binary[9]=g[9];for(j=8;j>=0;j=j-1)binary[j]=binary[j+1]^g[j];end endfunction
 wire[9:0]wl=wp-binary(rs1),rl=binary(ws1)-rp;
 reg request,command_up,prev_up,queued,queued_up;reg[1:0]mode;reg[2:0]warm,phase;
 reg[15:0]sample;reg[15:0]consumed;reg muted;reg[15:0]q;
 reg[1:0]req_sync,arm_sync,error_sync;reg seen,armed,error_flag;reg[1:0]sdstate;
 reg[31:0]lba;reg[15:0]left;reg[9:0]byte_count;reg[7:0]lo;reg bad;
 assign read_req=sdstate==1 || sdstate==3;assign read_addr=lba;
 always @(posedge sclk or posedge srst)begin
  if(srst)begin wp<=0;wg<=0;rs0<=0;rs1<=0;req_sync<=0;seen<=0;armed<=0;error_flag<=0;sdstate<=0;lba<=0;left<=0;byte_count<=0;lo<=0;bad<=0;end
  else begin
   rs0<=rg;rs1<=rs0;req_sync<={req_sync[0],request};
   if(sdstate==0 && req_sync[1]!=seen)begin
    seen<=req_sync[1];armed<=req_sync[1];wp<=0;wg<=0;error_flag<=0;bad<=0;
    lba<=480000;left<=command_up?UP_SAMPLES:DOWN_SAMPLES;byte_count<=0;sdstate<=1;
   end else if(read_error)begin error_flag<=1;sdstate<=0;end
   else case(sdstate)
    1:begin
     if(read_valid)begin
      if(byte_count==0&&read_data!="D" ||byte_count==1&&read_data!="I"||byte_count==2&&read_data!="R"||byte_count==3&&read_data!="1"||byte_count==4&&read_data!=1)bad<=1;
      byte_count<=byte_count+1'b1;
     end
     if(read_end)begin
      if(byte_count!=512||bad)begin error_flag<=1;sdstate<=0;end
      else begin lba<=command_up?UP_LBA:DOWN_LBA;byte_count<=0;sdstate<=2;end
     end
    end
    2:if(left!=0&&wl<256)begin byte_count<=0;sdstate<=3;end
    3:begin
     if(read_valid)begin
      byte_count<=byte_count+1'b1;
      if(!byte_count[0])lo<=read_data;
      else if(left!=0)begin
       mem[wp[8:0]]<={read_data,lo};wp<=wp+1'b1;wg<=((wp+10'd1)>>1)^(wp+10'd1);left<=left-1'b1;
      end
     end
     if(read_end)begin
      if(byte_count!=512)begin error_flag<=1;sdstate<=0;end
      else begin lba<=lba+1'b1;sdstate<=left==0?0:2;end
     end
    end
   endcase
  end
 end
 wire enabled=mode==2 && !muted && scene==0 && !eco;
 wire signed[15:0]voice_sample=phase==0?(rl!=0?q:16'd0):sample;
 wire signed[17:0]ml=($signed(in_left[23:8])>>>2)+($signed(voice_sample)<<<1);
 wire signed[17:0]mr=($signed(in_right[23:8])>>>2)+($signed(voice_sample)<<<1);
 function[23:0]clip;input signed[17:0]v;begin if(v>32767)clip=24'h7fff00;else if(v< -32768)clip=24'h800000;else clip={v[15:0],8'd0};end endfunction
 always @(posedge aclk or posedge arst)begin
  if(arst)begin
   rp<=0;rg<=0;ws0<=0;ws1<=0;q<=0;request<=0;command_up<=1;prev_up<=1;queued<=0;queued_up<=1;
   mode<=0;warm<=0;phase<=0;sample<=0;consumed<=0;muted<=0;arm_sync<=0;error_sync<=0;underflows<=0;out_valid<=0;out_left<=0;out_right<=0;
  end else begin
   ws0<=wg;ws1<=ws0;q<=mem[rp[8:0]];arm_sync<={arm_sync[0],armed};error_sync<={error_sync[0],error_flag};prev_up<=direction_up;
   if(scene!=0||eco)begin muted<=1;queued<=0;end
   if(direction_up!=prev_up && scene==0 && !eco)begin queued<=1;queued_up<=direction_up;end
   if(mode==0&&queued&&scene==0&&!eco)begin
    request<=~request;command_up<=direction_up;queued<=0;rp<=0;rg<=0;consumed<=0;phase<=0;warm<=0;muted<=0;mode<=1;
   end
   if(mode==1)begin
    if(arm_sync[1]==request)begin
     if(warm!=7)warm<=warm+1'b1;
     else if(error_sync[1])mode<=0;
     else if(rl>=256)mode<=2;
    end
   end
   if(mode==2 && error_sync[1])mode<=0;
   out_valid<=in_valid;
   if(in_valid)begin
    out_left<=enabled?clip(ml):in_left;
    out_right<=enabled?clip(mr):in_right;
    if(mode==2)begin
     if(phase==0)begin
      if(rl!=0)begin sample<=q;rp<=rp+1'b1;rg<=((rp+10'd1)>>1)^(rp+10'd1);consumed<=consumed+1'b1;phase<=1;end
      else if(underflows!=255)underflows<=underflows+1'b1;
     end else if(phase==5)begin phase<=0;if(consumed==(command_up?UP_SAMPLES:DOWN_SAMPLES))mode<=0;end
     else phase<=phase+1'b1;
    end
   end
  end
 end
endmodule
