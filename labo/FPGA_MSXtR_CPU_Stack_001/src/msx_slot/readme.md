# msx_slot.v 仕様

MSX カートリッジスロットのタイミングを生成するコントローラ。内部バス(`bus_*`, 42.95454MHz ドメイン)からの
アクセス要求を受け付け、MSX カートリッジスロットの信号仕様([テクハンwiki Appendix A.7](https://ngs.no.coocan.jp/doc/wiki.cgi/TechHan?page=Appendix+A%2E7+%A5%AB%A1%BC%A5%C8%A5%EA%A5%C3%A5%B8+%A5%CF%A1%BC%A5%C9%A5%A6%A5%A7%A5%A2%BB%C5%CD%CD)
のタイミングチャートに準拠した波形(`slot_*`, 214.7727MHz ドメインで生成)へ変換する。

## クロック

| 信号 | 周波数 | 周期 | 用途 |
| --- | --- | --- | --- |
| `clk_42m` | 42.95454MHz | 約23.28ns | 内部バスインターフェース(`bus_*`)のクロック |
| `clk_215m` | 214.7727MHz | 約4.657ns | スロットタイミング生成用の内部高速クロック(`clk_42m` のちょうど5倍) |

`slot_clock_n` は `clk_215m` を60分周(29カウントでH、59カウントで0に戻りL)して生成しており、周期は
60 × 4.657ns ≒ 279.4ns で、実機の Z80 クロック(3.579545MHz)相当になる。

## bus_* インターフェースの応答(`clk_42m` ドメイン)

- `bus_valid` かつ内部が空き(`~ff_bus_busy`)のときに要求を受け付け、`bus_m1`/`bus_address`/
  `bus_io`/`bus_write`/`bus_wdata` をラッチして `ff_bus_busy` を立てる。
- 要求受付と同時にトグル信号 `ff_req_toggle` を反転させ、`clk_215m` ドメインへ2段シンクロナイザで受け渡す
  (`ff_req_toggle_sync0/1/2`、エッジ検出で `w_req_event_215m` を生成)。
- `bus_ready` は `~ff_bus_busy` そのもの。要求受付後、対応するスロットアクセスが完了するまで `bus_ready` は 0 を維持する。
- スロット側アクセス完了は `ff_done_toggle` のトグルで `clk_42m` 側へ通知され(`ff_done_toggle_sync0/1/2` で同期、
  エッジ検出で `w_done_event_42m`)、これを受けて `ff_bus_busy` を落とし `bus_ready` を復帰させる。
- read アクセスの場合は完了通知と同時に `ff_slot_rdata` の値を `bus_rdata` にラッチし、1クロックだけ `bus_rdata_en` を
  アサートする。

## primary_slot / secondary_slot の取り込み

- `primary_slot`/`secondary_slot` は `clk_42m` ドメインの信号のため、`clk_215m` の単純な1段FF
  (`ff_primary_slot_215m`/`ff_secondary_slot_215m`)で受けてから使用する。

## アドレスとページ・スロットの対応

- `bus_address[15:14]` の2bit が「ページ番号」(0〜3)。64KBアドレス空間は16KB単位の4ページに分かれる。
- `primary_slot` は各ページで選択されている物理スロット番号(0〜3)を示す。`[1:0]`=ページ0, `[3:2]`=ページ1,
  `[5:4]`=ページ2, `[7:6]`=ページ3 に対応する。
- `secondary_slot` は、選択中の物理スロットが SLOT#0 または SLOT#3 の場合に、各ページで選択されている
  拡張(セカンダリ)スロット番号(0〜3)を示す。ビット割り当ては `primary_slot` と同じ(ページごとに2bit)。
- `w_page` = アクセス中のページ番号、`w_selected_slot` = `w_page` に応じて `ff_primary_slot_215m` から
  デコードした選択中の物理スロット番号、`w_selected_secondary_slot` = `w_page` に応じて
  `ff_secondary_slot_215m` からデコードした選択中の拡張スロット番号。
- `slot_sltsl0_n`〜`slot_sltsl3_n` は、`w_selected_slot` の値によっていずれか1本だけが Low になる
  (物理スロット選択信号)。ページ番号そのものでは選択しない。
- `slot_cs1_n`/`slot_cs2_n`/`slot_cs12_n` は、ページ番号(`w_page`)が1・2・1と2、かつ **read アクセス時のみ**
  Low になる(write アクセス時は主張しない)。

## ROM0 チップセレクトとアドレス生成

- ROM の下位14bit(`slot_a[13:0]`)は常に `bus_address[13:0]` の下位14bitがそのまま出力される。
- ROM の上位ビット(バンク番号)は、`bus_upper`/`bus_upper_address` のような外部入力ではなく、
  `w_selected_slot`/`w_selected_secondary_slot`/`w_page` から本モジュール内部で決定する(`w_rom0_bank`)。
- SLOT#0(任意の拡張スロット)、および SLOT#3 の拡張スロット1・2 にアクセスした場合のみ `slot_rom0_ce_n` が
  Low になる(`w_rom0_sel`)。それ以外(SLOT#1, SLOT#2, SLOT#3 の拡張スロット0・3)は通常どおり外部スロットの
  `slot_sltsl*_n` のみが有効になり、ROM0 は選択されない。
  - SLOT#0-0〜0-3: 各拡張スロットにつき32KB(ページ0・1のみ)を bank 0〜7 に割り当てる
    (`{2'd0, w_selected_secondary_slot, w_page[0]}`)。ページ2・3はページ0・1と同じ内容がミラーされる。
  - SLOT#3-1: 64KB全ページを bank 8〜11 に割り当てる(`5'd8 + w_page`)。
  - SLOT#3-2 ページ1(DiskROM): bank 12 固定。バンク切替レジスタは未実装のため常に BANK#0 を指す(TODO)。
- 漢字ROM(ROM1)は未対応。`slot_rom1_ce_n` は常に非アサート(Hi)。
- 詳細な ROM マップは本ファイル末尾の「ROMマップ」章を参照。

## アクセスステートマシン(`clk_215m` ドメイン、`ff_access_count`)

要求を受け付けると `ff_slot_clock_count == 0` のタイミング(slot_clock の立ち上がりに同期)で
`ff_busy_215m` を立て、`ff_access_count` を 0 から歩進しながら以下のタイミングでスロット信号を生成する。

| タイミング定数 | カウント値 | 経過時間(目安) | 内容 |
| --- | --- | --- | --- |
| `c_timing_start` | 0 | 0ns | アクセス開始 |
| `c_timing_command` | 31 | 約144ns | `slot_m1_n`(M1アクセス時)・`slot_rfsh_n`・`slot_iorq_n`・`slot_merq_n` が確定(コマンド確定) |
| `c_timing_select` | 34 | 約158ns | `slot_sltsl0_n`〜`3_n`・`slot_cs1_n`/`cs2_n`/`cs12_n`・`slot_rom0_ce_n`/`rom1_ce_n` が確定(スロット選択確定) |
| `c_timing_strobe` | 60 | 約279ns | `slot_rd_n`(read時)/`slot_wr_n`(write時) のストローブ開始 |
| `c_timing_read_sample` | 165 | 約768ns | read アクセス時、`slot_d` の値を1回だけサンプルして `ff_slot_rdata` に保持 |
| `c_timing_finish` | 179 | 約834ns | アクセス完了。`ff_done_toggle` を反転して `clk_42m` 側へ通知し、次の要求受付に戻る |

## /WAIT 処理(内部生成 + 外部信号)

- `bus_m1 = 1`(M1サイクル=命令フェッチ)のアクセスは、必ず `bus_io = 0` かつ `bus_write = 0` のメモリ読み出しである。
- M1サイクルでは、`slot_sltsl0_n`〜`3_n`・`slot_cs1_n`/`cs2_n` などが確定する `c_timing_select` の直後に、
  内部で1回だけ TW ステート相当の `/WAIT` を生成する(`ff_m1_wait_active`)。長さは `slot_clock` 1周期分
  (60 `clk_215m` サイクル ≒ 279ns)で、カウンタ(`ff_m1_wait_count`)により自動的に解除され、1アクセス中に
  再度挿入されることはない(`ff_m1_wait_done` でガード)。
- 外部の `slot_wait_n`(カートリッジ側からの `/WAIT`)は、アサートされている間はいつでも進行を止める。
- 内部生成の `/WAIT`(`w_m1_wait_n`)と外部の `slot_wait_n` を AND した信号が Low の間(`w_freeze`)は、
  `ff_access_count` の歩進を止める。これにより:
  - `bus_ready` は 0 を維持する(`ff_bus_busy` が下がらないため)。
  - `slot_clock_n` 以外のすべての `slot_*` 出力信号は、その時点の値のまま変化しない
    (すべて `ff_access_count` およびラッチ済みの要求内容から組合せ生成されているため)。
- `wait_n` という独立した出力ポートは持たない(内部の `/WAIT` 生成と `slot_wait_n` の待ち合わせは、
  本モジュール内でアクセスの一時停止として完結する)。

## その他の内部的な特徴

- `slot_oe_n` は常時 0 固定(常にバッファ出力イネーブル)。
- `slot_reset_n` は `reset_n` をそのまま出力。
- `slot_data_dir` は write アクセス中のみ 1(モジュール側からスロットへ駆動)、それ以外は `slot_busdir` をそのまま
  スルーする。
- `slot_d` は write アクセス中のみ `ff_req_wdata_215m` を駆動し、それ以外は `8'hzz`(ハイインピーダンス)。
- `int_n` は `slot_int_n` を、そのまま出力する。

# 拡張スロット
SLOT#0 の FFFFh、SLOT#3 の FFFFh には、それぞれ拡張スロット選択レジスタが存在する。
これらの読み書きをする際は、slot_wr_n, slot_rd_n は H のままである。
8bit の値を書き込め、かつ読み出すと書き込んだ値が反転して読み出される。
初期値は、両方とも 00h である。
この 8bit は、primary_slot と同様に、2bit 単位で分かれており、各ページの拡張スロット番号を示す。
SLOT#{基本スロット番号}-{拡張スロット番号} で SLOT#0 には SLOT#0-0, SLOT#0-1, SLOT#0-2, SLOT#0-3 の 4つの拡張スロットがあり、SLOT#3 には SLOT#3-0, SLOT#3-1, SLOT#3-2, SLOT#3-3 の 4つの拡張スロットがある。
このそれぞれに 64KB の空間があり、各ページ単位でどの拡張スロットが出現するかを指定できる。
拡張スロットの英語表記は、secondary_slot である。
FFFFh の拡張スロット選択レジスタは、拡張スロット選択レジスタに影響を受けず、すべての拡張スロットで同じレジスタが出現する。
SLOT#0-0, 0-1, 0-2, 0-3, 3-1, 3-2 にアクセスする際は、slot_rom0_ce_n = L になる。
漢字ROM にアクセスする際は 、slot_rom1_ce_n = L になる。

# 漢字ROM
I/O の D8h, D9h は JIS1漢字ROM, DAh, DBh は JIS2漢字ROM が接続されている。


# ROMマップ
slot_a, slot_wr_n, slot_rd_n, slot_d は、MSX カートリッジスロットだけでなく、２つの 512KB フラッシュROM にも接続されている。
そのチップセレクトが、slot_rom0_ce_n, slot_rom1_ce_n である。
特定のスロットにアクセスする際に、slot_rom0_ce_n, slot_rom1_ce_n が Low になる。

ROM0
00000h +---------------------+
       | MAIN-ROM前半 16KB   | SLOT#0-0 page0
04000h +---------------------+
	   | MAIN-ROM後半 16KB   | SLOT#0-0 page1
08000h +---------------------+
       | Option-ROM0 16KB    | SLOT#0-1 page0
0C000h +---------------------+
	   | Option-ROM1 16KB    | SLOT#0-1 page1
10000h +---------------------+
	   | Option-ROM2 16KB    | SLOT#0-2 page0
14000h +---------------------+
	   | MSX-MUSIC 16KB      | SLOT#0-2 page1
18000h +---------------------+
	   | Option-ROM3 16KB    | SLOT#0-3 page0
1C000h +---------------------+
	   | Boot Logo 16KB      | SLOT#0-3 page1
20000h +---------------------+
	   | EXT-ROM 16KB        | SLOT#3-1 page0
24000h +---------------------+
	   | KanjiDriver0 16KB   | SLOT#3-1 page1
28000h +---------------------+
	   | KanjiDriver1 16KB   | SLOT#3-1 page2
2C000h +---------------------+
	   | Option-ROM4 16KB    | SLOT#3-1 page3
30000h +---------------------+
	   | DiskROM 16KB        | SLOT#3-2 page1 (BANK#0)
34000h +---------------------+
	   | DiskROM 16KB        | SLOT#3-2 page1 (BANK#1)
38000h +---------------------+
	   | DiskROM 16KB        | SLOT#3-2 page1 (BANK#2)
3C000h +---------------------+
	   | DiskROM 16KB        | SLOT#3-2 page1 (BANK#3)
40000h +---------------------+

ROM1
00000h +---------------------+
	   | KanjiROM 128KB      | JIS1 Kanji
10000h +---------------------+
	   | KanjiROM 128KB      | JIS2 Kanji
20000h +---------------------+
	   | Reserved 256KB      | Reserved
40000h +---------------------+
