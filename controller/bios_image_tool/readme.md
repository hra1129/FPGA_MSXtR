# ROMマップ
slot_a, slot_wr_n, slot_rd_n, slot_d は、MSX カートリッジスロットだけでなく、２つの 512KB フラッシュROM にも接続されている。
そのチップセレクトが、slot_rom0_ce_n, slot_rom1_ce_n である。
特定のスロットにアクセスする際に、slot_rom0_ce_n, slot_rom1_ce_n が Low になる。

ROM0 msxtr.rom
00000h +---------------------+
       | MAIN-ROM前半 16KB   | SLOT#0-0 page0			bios/a1stbios.rom 0000h-3FFFh
04000h +---------------------+
	   | MAIN-ROM後半 16KB   | SLOT#0-0 page1			bios/a1stbios.rom 4000h-7FFFh
08000h +---------------------+
       | Option-ROM0 16KB    | SLOT#0-1 page0			ff_fill.rom 0000h-3FFFh
0C000h +---------------------+
	   | Option-ROM1 16KB    | SLOT#0-1 page1			ff_fill.rom 0000h-3FFFh
10000h +---------------------+
	   | Option-ROM2 16KB    | SLOT#0-2 page0			ff_fill.rom 0000h-3FFFh
14000h +---------------------+
	   | MSX-MUSIC 16KB      | SLOT#0-2 page1			bios/a1stmus.rom 0000h-3FFFh
18000h +---------------------+
	   | Option-ROM3 16KB    | SLOT#0-3 page0			ff_fill.rom 0000h-3FFFh
1C000h +---------------------+
	   | Boot Logo 16KB      | SLOT#0-3 page1			bios/a1stopt.rom 0000h-3FFFh
20000h +---------------------+
	   | EXT-ROM 16KB        | SLOT#3-1 page0			bios/a1stext.rom 0000h-3FFFh
24000h +---------------------+
	   | KanjiDriver0 16KB   | SLOT#3-1 page1			bios/a1stkdr.rom 0000h-3FFFh
28000h +---------------------+
	   | KanjiDriver1 16KB   | SLOT#3-1 page2			bios/a1stkdr.rom 4000h-7FFFh
2C000h +---------------------+
	   | Option-ROM4 16KB    | SLOT#3-1 page3			ff_fill.rom 0000h-3FFFh
30000h +---------------------+
	   | DiskROM 16KB        | SLOT#3-2 page1 (BANK#0)	bios/a1stdosb.rom
34000h +---------------------+
	   | DiskROM 16KB        | SLOT#3-2 page1 (BANK#1)	bios/a1stdosb.rom
38000h +---------------------+
	   | DiskROM 16KB        | SLOT#3-2 page1 (BANK#2)	bios/a1stdosb.rom
3C000h +---------------------+
	   | DiskROM 16KB        | SLOT#3-2 page1 (BANK#3)	bios/a1stdosb.rom
40000h +---------------------+
	   | Reserved 256KB      | Reserved					ff_fill.rom 0000h-3FFFh * 16
80000h +---------------------+

ROM1 kanji.rom
00000h +---------------------+
	   | KanjiROM 128KB      | JIS1 Kanji				bios/a1stkfn.rom 00000h-1FFFFh
20000h +---------------------+
	   | KanjiROM 128KB      | JIS2 Kanji				bios/a1stkfn.rom 20000h-3FFFFh
40000h +---------------------+
	   | Reserved 256KB      | Reserved					ff_fill.rom 0000h-3FFFh * 16
80000h +---------------------+
