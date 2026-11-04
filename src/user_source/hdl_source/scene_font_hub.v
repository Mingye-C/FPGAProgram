module scene_font_hub(input clk,
 input [12:0] chart_a,floor_a,parameter_a,parameter_b,subtitle_a,subtitle_b,page_a,
 input [14:0] subtitle_cn_a,subtitle_cn_b,page_cn_a,
 input [10:0] floor_text,subtitle_text_a,subtitle_text_b,page_text,parameter_text_a,parameter_text_b,
 output [7:0] text_a,text_b,
 output [7:0] ascii_a,ascii_b,output chinese_a,chinese_b);
wire [9:0] ta=page_text[10]?page_text[9:0]:floor_text[10]?floor_text[9:0]:parameter_text_a[10]?parameter_text_a[9:0]:subtitle_text_a[9:0];
scene_text_rom u_map(.clk(clk),.address(ta),.address_b(parameter_text_b[10]?parameter_text_b[9:0]:subtitle_text_b[9:0]),.code(text_a),.code_b(text_b));
wire [12:0] a=chart_a[12]?chart_a:page_a[12]?page_a:floor_a[12]?floor_a:parameter_a[12]?parameter_a:subtitle_a;
wire [12:0] b=parameter_b[12]?parameter_b:subtitle_b;
wire [13:0] ca=page_cn_a[14]?page_cn_a[13:0]:subtitle_cn_a[13:0];
subtitle_compact_rom u_ascii(.clk(clk),.a(a[11:4]),.ar(a[3:0]),.b(b[11:4]),.br(b[3:0]),.ap(ascii_a),.bp(ascii_b));
scene_chinese_rom u_chinese(.clk(clk),.a(ca),.b(subtitle_cn_b[13:0]),.ap(chinese_a),.bp(chinese_b));
`ifndef SYNTHESIS
always @(posedge clk)begin
 if((page_text[10]+{2'd0,floor_text[10]}+{2'd0,subtitle_text_a[10]}+{2'd0,parameter_text_a[10]})>1)$fatal(1,"Text map collision");
 if((chart_a[12]+{2'd0,page_a[12]}+{2'd0,floor_a[12]}+{2'd0,parameter_a[12]}+{2'd0,subtitle_a[12]})>1)$fatal(1,"ASCII font A collision");
 if(parameter_text_b[10] && subtitle_text_b[10])$fatal(1,"Text map B collision");
 if(parameter_b[12] && subtitle_b[12])$fatal(1,"ASCII font B collision");
 if(page_cn_a[14] && subtitle_cn_a[14])$fatal(1,"Chinese font collision");
end
`endif
endmodule
