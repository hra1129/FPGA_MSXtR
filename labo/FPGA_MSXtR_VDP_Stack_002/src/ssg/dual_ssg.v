//
//	dual_ssg.v
//	DualSSG (YM2149. AY-3-8910 Compatible Processor)
//
//	Copyright (C) 2026 Takayuki Hara
//
//	譛ｬ繧ｽ繝輔ヨ繧ｦ繧ｧ繧｢縺翫ｈ縺ｳ譛ｬ繧ｽ繝輔ヨ繧ｦ繧ｧ繧｢縺ｫ蝓ｺ縺･縺・※菴懈・縺輔ｌ縺滓ｴｾ逕溽黄縺ｯ縲∽ｻ･荳九・譚｡莉ｶ繧・//	貅縺溘☆蝣ｴ蜷医↓髯舌ｊ縲∝・鬆貞ｸ・♀繧医・菴ｿ逕ｨ縺瑚ｨｱ蜿ｯ縺輔ｌ縺ｾ縺吶・//
//	1.繧ｽ繝ｼ繧ｹ繧ｳ繝ｼ繝牙ｽ｢蠑上〒蜀埼貞ｸ・☆繧句ｴ蜷医∽ｸ願ｨ倥・闡嶺ｽ懈ｨｩ陦ｨ遉ｺ縲∵悽譚｡莉ｶ荳隕ｧ縲√♀繧医・荳玖ｨ・//	  蜈崎ｲｬ譚｡鬆・ｒ縺昴・縺ｾ縺ｾ縺ｮ蠖｢縺ｧ菫晄戟縺吶ｋ縺薙→縲・//	2.繝舌う繝翫Μ蠖｢蠑上〒蜀埼貞ｸ・☆繧句ｴ蜷医・貞ｸ・黄縺ｫ莉伜ｱ槭・繝峨く繝･繝｡繝ｳ繝育ｭ峨・雉・侭縺ｫ縲∽ｸ願ｨ倥・
//	  闡嶺ｽ懈ｨｩ陦ｨ遉ｺ縲∵悽譚｡莉ｶ荳隕ｧ縲√♀繧医・荳玖ｨ伜・雋ｬ譚｡鬆・ｒ蜷ｫ繧√ｋ縺薙→縲・//	3.譖ｸ髱｢縺ｫ繧医ｋ莠句燕縺ｮ險ｱ蜿ｯ縺ｪ縺励↓縲∵悽繧ｽ繝輔ヨ繧ｦ繧ｧ繧｢繧定ｲｩ螢ｲ縲√♀繧医・蝠・･ｭ逧・↑陬ｽ蜩√ｄ豢ｻ蜍・//	  縺ｫ菴ｿ逕ｨ縺励↑縺・％縺ｨ縲・//
//	譛ｬ繧ｽ繝輔ヨ繧ｦ繧ｧ繧｢縺ｯ縲∬送菴懈ｨｩ閠・↓繧医▲縺ｦ縲檎樟迥ｶ縺ｮ縺ｾ縺ｾ縲肴署萓帙＆繧後※縺・∪縺吶り送菴懈ｨｩ閠・・縲・//	迚ｹ螳夂岼逧・∈縺ｮ驕ｩ蜷域ｧ縺ｮ菫晁ｨｼ縲∝膚蜩∵ｧ縺ｮ菫晁ｨｼ縲√∪縺溘◎繧後↓髯仙ｮ壹＆繧後↑縺・√＞縺九↑繧区・遉ｺ
//	逧・ｂ縺励￥縺ｯ證鈴ｻ吶↑菫晁ｨｼ雋ｬ莉ｻ繧りｲ縺・∪縺帙ｓ縲り送菴懈ｨｩ閠・・縲∽ｺ狗罰縺ｮ縺・°繧薙ｒ蝠上ｏ縺壹∵錐螳ｳ
//	逋ｺ逕溘・蜴溷屏縺・°繧薙ｒ蝠上ｏ縺壹√°縺､雋ｬ莉ｻ縺ｮ譬ｹ諡縺悟･醍ｴ・〒縺ゅｋ縺句宍譬ｼ雋ｬ莉ｻ縺ｧ縺ゅｋ縺具ｼ磯℃螟ｱ
//	縺昴・莉悶・・我ｸ肴ｳ戊｡檎ぜ縺ｧ縺ゅｋ縺九ｒ蝠上ｏ縺壹∽ｻｮ縺ｫ縺昴・繧医≧縺ｪ謳榊ｮｳ縺檎匱逕溘☆繧句庄閭ｽ諤ｧ繧堤衍繧・//	縺輔ｌ縺ｦ縺・◆縺ｨ縺励※繧ゅ∵悽繧ｽ繝輔ヨ繧ｦ繧ｧ繧｢縺ｮ菴ｿ逕ｨ縺ｫ繧医▲縺ｦ逋ｺ逕溘＠縺滂ｼ井ｻ｣譖ｿ蜩√∪縺溘・莉｣逕ｨ繧ｵ
//	繝ｼ繝薙せ縺ｮ隱ｿ驕斐∽ｽｿ逕ｨ縺ｮ蝟ｪ螟ｱ縲√ョ繝ｼ繧ｿ縺ｮ蝟ｪ螟ｱ縲∝茜逶翫・蝟ｪ螟ｱ縲∵･ｭ蜍吶・荳ｭ譁ｭ繧ょ性繧√√∪縺溘◎
//	繧後↓髯仙ｮ壹＆繧後↑縺・ｼ臥峩謗･謳榊ｮｳ縲・俣謗･謳榊ｮｳ縲∝・逋ｺ逧・↑謳榊ｮｳ縲∫音蛻･謳榊ｮｳ縲∵・鄂ｰ逧・錐螳ｳ縲√∪
//	縺溘・邨先棡謳榊ｮｳ縺ｫ縺､縺・※縲∽ｸ蛻・ｲｬ莉ｻ繧定ｲ繧上↑縺・ｂ縺ｮ縺ｨ縺励∪縺吶・//
//	Note that above Japanese version license is the formal document.
//	The following translation is only for reference.
//
//	Redistribution and use of this software or any derivative works,
//	are permitted provided that the following conditions are met:
//
//	1. Redistributions of source code must retain the above copyright
//	   notice, this list of conditions and the following disclaimer.
//	2. Redistributions in binary form must reproduce the above
//	   copyright notice, this list of conditions and the following
//	   disclaimer in the documentation and/or other materials
//	   provided with the distribution.
//	3. Redistributions may not be sold, nor may they be used in a
//	   commercial product or activity without specific prior written
//	   permission.
//
//	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//	"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//	LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
//	FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
//	COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
//	INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//	BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//	LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//	CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
//	LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
//	ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//	POSSIBILITY OF SUCH DAMAGE.
//
//-----------------------------------------------------------------------------

module dual_ssg #(
	parameter		BUILTIN = 1
) (
	input			clk,
	input			reset_n,
	input			enable,
	input			bus_cs,
	input			bus_valid,
	input			bus_write,
	input	[1:0]	bus_address,
	output			bus_ready,
	input	[7:0]	bus_wdata,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,

	input	[7:0]	ssg_ioa0,
	output	[7:0]	ssg_iob0,
	input	[7:0]	ssg_ioa1,
	output	[7:0]	ssg_iob1,

	output	[11:0]	sound_out0,			//	10bit/ch * 3ch = 12bit
	output	[11:0]	sound_out1,			//	10bit/ch * 3ch = 12bit
	input	[1:0]	mode				//	0: disable, 1: single(core0), 2: single(core1), 3: dual
);
	wire	[7:0]	w_rdata0;
	wire			w_rdata_en0;
    wire            w_bus_ssg_ready0;
	wire	[7:0]	w_rdata1;
	wire			w_rdata_en1;
    wire            w_bus_ssg_ready1;

	ssg_core #( 
		.builtin		( BUILTIN			),
		.core_number	( 1'b0				)
	) ssg_core0 (
		.clk			( clk				),
		.reset_n		( reset_n			),
		.enable			( enable			),
		.bus_ioreq		( bus_cs			),
		.bus_valid		( bus_valid			),
		.bus_write		( bus_write			),
		.bus_address	( bus_address		),
		.bus_ready		( w_bus_ssg_ready0	),
		.bus_wdata		( bus_wdata			),
		.bus_rdata		( w_rdata0			),
		.bus_rdata_en	( w_rdata_en0		),
		.ssg_ioa		( ssg_ioa0			),
		.ssg_iob		( ssg_iob0			),
		.sound_out		( sound_out0		),
		.mode			( mode				)
	);

	ssg_core #( 
		.builtin		( 1'b1				),
		.core_number	( 1'b1				)
	) ssg_core1 (
		.clk			( clk				),
		.reset_n		( reset_n			),
		.enable			( enable			),
		.bus_ioreq		( bus_cs			),
		.bus_valid		( bus_valid			),
		.bus_write		( bus_write			),
		.bus_address	( bus_address		),
		.bus_ready		( w_bus_ssg_ready1	),
		.bus_wdata		( bus_wdata			),
		.bus_rdata		( w_rdata1			),
		.bus_rdata_en	( w_rdata_en1		),
		.ssg_ioa		( ssg_ioa1			),
		.ssg_iob		( ssg_iob1			),
		.sound_out		( sound_out1		),
		.mode			( mode				)
	);

    assign bus_ready        = w_bus_ssg_ready0 | w_bus_ssg_ready1;
	assign bus_rdata		= w_rdata0 & w_rdata1;
	assign bus_rdata_en		= w_rdata_en0 | w_rdata_en1;
endmodule
