// --------------------------------------------------------------------
//	IKAOPLL Wrapper
// ====================================================================
//	2026/01/22 t.hara
// --------------------------------------------------------------------

module dual_opll (
	input			clk,
	input			reset_n,
	input			enable,
	input			bus_cs,
	input	[1:0]	bus_address,
	input			bus_write,
	input			bus_valid,
	output			bus_ready,
	input	[7:0]	bus_wdata,
	output	[15:0]	sound_out0,				//	signed
	output	[15:0]	sound_out1				//	signed
);
	wire			w_cs0_n;
	wire			w_cs1_n;
	wire	[15:0]	w_sound_out;

	// --------------------------------------------------------------------
	//	Address decoder
	// --------------------------------------------------------------------
	assign w_cs0_n		= ( bus_cs && !bus_address[1] ) ? ~bus_valid: 1'b1;
	assign w_cs1_n		= ( bus_cs &&  bus_address[1] ) ? ~bus_valid: 1'b1;
	assign bus_ready	= (~(w_cs0_n & w_cs1_n) & enable) | (w_cs0_n & w_cs1_n);

	// --------------------------------------------------------------------
	//	IKAOPLL body
	// --------------------------------------------------------------------
	IKAOPLL #(
		.FULLY_SYNCHRONOUS			( 1					),		//	use DFF only
		.FAST_RESET					( 1					),		//	speed up reset
		.ALTPATCH_CONFIG_MODE		( 0					),		//	0 to use external wire, 1 to use bit[4] of TEST register
		.USE_PIPELINED_MULTIPLIER	( 1					)		//	1 to add pipelined multiplier to increase fmax
	) u_ikaopll0 (
		.i_XIN_EMUCLK				( clk				),
		.o_XOUT						( 					),		//	no use: Clock output
		.i_phiM_PCEN_n				( ~enable			),
		.i_IC_n						( reset_n			),
		.i_ALTPATCH_EN				( 1'b0				),		//	VRC7 patch disable
		.i_CS_n						( w_cs0_n			),
		.i_WR_n						( ~bus_write		),
		.i_A0						( bus_address[0]	),
		.i_D						( bus_wdata			),
		.o_D						( 					),		//	no use: Read test bits
		.o_D_OE						( 					),		//	no use: o_D enable
		.o_DAC_EN_MO				( 					),		//	no use
		.o_DAC_EN_RO				( 					),		//	no use
		.o_IMP_NOFLUC_SIGN			( 					),		//	no use
		.o_IMP_NOFLUC_MAG			( 					),		//	no use
		.o_IMP_FLUC_SIGNED_MO		( 					),		//	no use
		.o_IMP_FLUC_SIGNED_RO		( 					),		//	no use
		.i_ACC_SIGNED_MOVOL			( 5'd10				),		//	Melody volume level: -16...15 (SIGNED)
		.i_ACC_SIGNED_ROVOL			( 5'd15				),		//	Drum volume level  : -16...15 (SIGNED)
		.o_ACC_SIGNED_STRB			( 					),		//	no use
		.o_ACC_SIGNED				( sound_out0		)		//	sound out
	);

	IKAOPLL #(
		.FULLY_SYNCHRONOUS			( 1					),		//	use DFF only
		.FAST_RESET					( 1					),		//	speed up reset
		.ALTPATCH_CONFIG_MODE		( 0					),		//	0 to use external wire, 1 to use bit[4] of TEST register
		.USE_PIPELINED_MULTIPLIER	( 1					)		//	1 to add pipelined multiplier to increase fmax
	) u_ikaopll1 (
		.i_XIN_EMUCLK				( clk				),
		.o_XOUT						( 					),		//	no use: Clock output
		.i_phiM_PCEN_n				( ~enable   		),
		.i_IC_n						( reset_n			),
		.i_ALTPATCH_EN				( 1'b0				),		//	VRC7 patch disable
		.i_CS_n						( w_cs1_n			),
		.i_WR_n						( ~bus_write		),
		.i_A0						( bus_address[0]	),
		.i_D						( bus_wdata			),
		.o_D						( 					),		//	no use: Read test bits
		.o_D_OE						( 					),		//	no use: o_D enable
		.o_DAC_EN_MO				( 					),		//	no use
		.o_DAC_EN_RO				( 					),		//	no use
		.o_IMP_NOFLUC_SIGN			( 					),		//	no use
		.o_IMP_NOFLUC_MAG			( 					),		//	no use
		.o_IMP_FLUC_SIGNED_MO		( 					),		//	no use
		.o_IMP_FLUC_SIGNED_RO		( 					),		//	no use
		.i_ACC_SIGNED_MOVOL			( 5'd10				),		//	Melody volume level: -16...15 (SIGNED)
		.i_ACC_SIGNED_ROVOL			( 5'd15				),		//	Drum volume level  : -16...15 (SIGNED)
		.o_ACC_SIGNED_STRB			( 					),		//	no use
		.o_ACC_SIGNED				( sound_out1		)		//	sound out
	);
endmodule
