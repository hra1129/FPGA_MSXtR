# クロック設定
IP Core Generator --> Hard Module/CLOCK/PLL_ADV

Common
	☑General Mode
	CLKIN
		Clock Frequency(19~800)MHz: 28.640MHz  ※実クロック 28.63636MHz
	mDRP Clock Frequency
		mDRP Clock Frequency(1~100) 50MHz
	VCO Frequency
		CLKFB
			Source ☑Internal

Clkout0
	Expected Frequency(5.469~1400)MHz: 200.48MHz   ※ 28.64 * 7 = 200.48  ※実クロック 200.45452MHz
	Tolerance(%): 0.0
	Phase(degree)
	☑Static 0

Clkout1
	Expected Frequency(5.469~1400)MHz: 42.96MHz   ※ 28.64 * 1.5 = 42.96  ※実クロック 42.95454MHz
	Tolerance(%): 0.0
	Phase(degree)
	☑Static 0
