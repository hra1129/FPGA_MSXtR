# 概要
カートリッジが動くようになったので、
CPUのテストベンチを作りましょう。

搭載している cz80, cr800 は、すべての命令が正しく動作しているかの保証がありません。
512KB の ASCII8K のマッパーのメガROM で、Z80全命令・R800全命令のレジスタ値変化・フラグ変化を網羅的にチェックするテストプログラムを作成してください。

Z80は添付の資料を参考に、
R800 は、下記サイトを参考にしてください。
https://d4.princess.ne.jp/msx/datas/R800UM/r800op.html

網羅的にテストして、徹底的に問題点を見つけるのが目的です。

動作の経過が分かるように、画面モードは SCREEN 1:COLOR 15,4,7 の表示で
トータルのテスト項目数・実施済みテスト項目数・エラー発生テスト項目数を
一番上に、
下に進捗状況が分かるような表示（暴走してハングしていないことの確認）を
出して、エラーが発生した場合はその内容を表示するようにしてください。
トータルなどが表示されている行は固定で常に表示して置き、
それより下はスクロール表示で、エラー多数の場合はスクロールが流れる形で
OKです。

アセンブラは、zma.exe を使用してください。

# 実装

## ファイル
| ファイル | 内容 |
|---|---|
| cpu_test.asm | テストランナー（ROM 先頭 16KB、ASCII8K バンク 0/1） |
| stub.asm | RAM (C000h) に常駐し、被テスト命令を実行してレジスタを保存するスタブ |
| cpu_test_def.asm | 共通定数（make_tests.py からも読み込む） |
| make_tests.py | テストデータ生成・ROM 組み立て |
| zt_engine.asm | z80test（raxoft/z80test、MIT ライセンス）のテストエンジン idea.asm の移植 |
| zt_full.asm / zt_ccf.asm / zt_memptr.asm / zt_doc.asm | エンジンのバリアント（ZT / Q / WZ / R800 用） |
| z80test_port.py | z80test の tests.asm を読み込み、テストレコードと期待 CRC を生成する |
| z80test\ | z80test の tests.asm / testmacros.asm / license.txt / readme.txt（原版のまま） |
| build.bat | ビルド |
| cpu_test.rom | 生成物（512KB, ASCII8K） |

## ビルド
Python 3 と、Z80 エミュレータパッケージ `z80` が必要。

    pip install z80
    build.bat

1. zma で stub.asm → stub.bin、cpu_test.asm → runner.bin、zt_*.asm → zt_*.bin
2. make_tests.py が、同じ stub.bin / zt_*.bin を Python の Z80 モデル上で実行して全テストの期待値を生成し、
   runner.bin + テストデータを 512KB の cpu_test.rom にまとめる（生成に 1〜2 分かかる）。

## 方式
- 1 テスト = 1 命令（または未定義命令）。入力状態（全レジスタ・裏レジスタ・SP・I・PSG R#0・
  D000h〜D01Fh のメモリウィンドウ）を xorshift16 で生成し、命令ごとの制約（メモリを指すレジスタの範囲、
  ポート番号、分岐オフセット等）を上書きしてから実行する。
- 実行後の全レジスタ・F・メモリウィンドウ・PSG・分岐の行き先（そのまま / 分岐先 / RST nn）を
  期待値と比較する。期待値は入力との差分だけを ROM に格納している。
- 8bit 算術演算・回転シフト・DAA/CPL/SCF/CCF/NEG/INC A/DEC A などは、A（および F）の
  全組み合わせを総当たりし、結果をチェックサム化して比較する（項目名 `ALL ...`）。
- Z80 スイートを実行後、turbo R であれば CHGCPU で R800(ROM) モードに切り替えて R800 スイートを実行する。
  turbo R 以外では R800 スイートはスキップする。

## z80test の移植（項目名 `ZT` / `WZ`）
既存テストの後に、z80test（https://github.com/raxoft/z80test）の全テストを実行する。
z80test は 1 命令につき数千〜数万通りのレジスタ・フラグの組み合わせを実行し、結果を CRC-32 にまとめて比較する。
既存テストにない次の観点を補う。
- `ZT`  : 全レジスタ・全フラグ（X/Y を含む）。z80full 相当。SCF/CCF は NEC / ST 版と FS-A1GT（T9769）の結果も可とし、
  その場合は `=NEC` / `=ST` / `=TR` の注記行を出す。
  - `=TR`: FS-A1GT の実機で得た規則（直前の命令がフラグを変えない場合に Y = F.Y、X = (F or A).X）。
- `Q`（z80ccf 相当。各命令の直後に CCF を実行し、Q レジスタの挙動を見る）は使わない。
  FS-A1GT の Z80（T9769）は Zilog の Q の規則（(Q xor F) or A）に従わず、規則も特定できていないため。
  エンジン（zt_ccf.asm）と生成コードは残してある。
- `WZ`  : 各命令の直後に BIT 0,(HL) を実行し、内部レジスタ MEMPTR(WZ) の値を F の X/Y で見る。z80memptr 相当。
- R800 : 公開フラグのみ（z80doc 相当）。R800 で定義の異なる命令はスキップし、ADD/ADC/SBC HL の H と BIT の S/P は比較しない。

実装:
- エンジン（zt_*.bin）は type 3 レコードとして ROM に置き、C400h に転送して実行する。
  各テスト（type 2 レコード）は、名前・期待 CRC（代替 CRC と注記ラベル付き）・テストベクタを持つ。
- ポート FEh を使う IN/OUT 系テストは、PSG のポート（IN = A2h、OUT = A1h、R#0 = BFh）に置き換えている。
- 期待 CRC は、同じエンジンを Python の Z80 モデル（kosarev `z80`）で実行して求める。
  このモデルにない Zilog の挙動は、テスト対象の命令を 1 命令ずつ実行して補正している。
  - Q: SCF/CCF の X/Y = ((Q xor F) or A)
  - INI/IND の MEMPTR = BC ± 1
  - 中断されたブロックリピート命令（`->NOP'` の項目）: X/Y = PC の上位バイト、INxR/OTxR の H/PV の変化、MEMPTR = PC + 1
- 補正後の値は、原版と同じアドレス配置で実行すると、tests.asm に書かれている実機（Zilog）の CRC と一致することを確認した。
- 次の場合は旧来の挙動も可とし、注記行を出す（エラーには数えない）。
  - `=NOQ`: Q を持たない CPU の結果
  - `=OLD`: 中断されたブロック命令でフラグが変化しない CPU の結果
- NG の場合は `G:`（実測 CRC）と `E:`（期待 CRC）を表示する。CRC なので、どの組み合わせで違ったかは分からない。

## 画面
- 1 行目: `TOT`（総テスト項目数） / `DONE`（実施済み） / `ERR`（エラー項目数）を常時表示。
- 2 行目: 実行中の CPU・テスト番号・命令名（ALL 系は右端の記号が回転し、ハングしていないことを示す）。
- 4 行目以降: エラー表示（スクロール）。エラー項目ごとに最初に失敗したベクタの
  命令バイト列と、不一致の項目（I: 入力 / E: 期待値 / G: 実測値）を最大 4 項目表示し、
  最後に失敗ベクタ数 / 総ベクタ数を表示する。
- 項目名の `(U)` は未定義（undocumented）命令。

## 起動時のキー
- `R` キーを押しながら起動すると、Z80 スイートを飛ばして R800 スイートから実行する（turbo R のみ）。
  DONE は Z80 の項目数から数え始めるので、テスト番号は通常実行と同じになる。

## R800 の扱い（openMSX の R800 実装と d4.princess の資料に準拠。FS-A1GT の実機結果で補正）
- 未定義フラグ X/Y（bit5, bit3）は比較しない。
- 仕様が異なる / 不定のため比較しないフラグ: CCF と ADD/ADC/SBC HL の H、BIT の S/P、ブロック IN/OUT の S/H/P。
- ブロック IN/OUT の F は「入力の F から Z/N を差し替えたもの（Z = B==0、N = 1）」を期待する。
- SLL (CB 30-37) は SLA と同じ動作を期待する。DD/FD CB 30-37 はテストしない。
- DD/FD CB d xx の z≠6（結果をレジスタにもコピーする非公式形）は、FS-A1GT の実機に合わせて 4 バイトの NOP を期待する。
- DD/FD + HL を使わない命令は、2 バイトの NOP を期待する（Z80 ではプレフィックス無視）。
- MULUB / MULUW をテストする。LD R,A → LD A,R の組はテストしない。
- OUT (C),0（ED 71）はテストしない。FS-A1GT の実機では、直後のオペコードが A に置き換わることが多いが、
  約 3% の確率で置き換わらず、結果が一定しないため。z80test の OUT (C),R も ED 71 を含むため対象外。
- MULUB の非公式形は実機（Grauw「Uncovering the R800」）に合わせ、ED E1 / E9 / F9 を A,H / A,L / A,A、
  ED F1 を A,A として期待する。MULUW の非公式形（ED D3 / E3）とミラー（ED CB / DB / EB / FB）は、
  結果の規則が分かっていないためテストしない。
- NEG のミラー（ED 4C / 54 / 5C / 64 / 6C / 74 / 7C）と RETN のミラー（ED 55 / 5D / 65 / 6D / 75 / 7D）は、
  FS-A1GT の実機に合わせて NOP を期待する。
- ED 63 nn nn（LD (nn),HL の別形）は、FS-A1GT の実機では 4 バイト命令で、(nn) には書かずに
  6363h に H を書く（nn やほかのレジスタには依存しない）。6363h はこの ROM（ASCII8K）のバンク 0 レジスタに
  当たるため、通常のベクタではなく専用テスト（レコード 04）で、ページ 1 を RAM に切り替えて実行する。
  HL を 6 通りに変えて、6363h = H、6362h / 6364h と (nn) が不変、HL が不変であることを確認する。
- ED 6B nn nn（LD HL,(nn) の別形）は、4 バイト命令で HL = EB6Bh になることを期待する
  （FS-A1GT の実機の RAM 上での結果。H の値は実行環境によって変わる可能性がある）。
- ED 82 / 8A / 92 / 9A は 3 バイト命令になるため、テストしない（Grauw「Uncovering the R800」と一致）。
  z80test の LD RR,(NN) / LD (NN),RR も対象外。

## 診断用 ROM（ed_nn_test.rom）
- 16KB の ROM。ED 43〜7B の `LD (nn),rr` / `LD rr,(nn)` 系を Z80 と R800 で実行し、
  命令長（SP の値）とレジスタ値、JIFFY の差分を表示する。R800 では ED 63 を DI と EI の両方で実行する。
- ED 63 はページ 1 の 6363h に書き込むため、カートリッジ上で実行するとバンクが切り替わって暴走する。
  ed63_test.rom（ed63_test.asm / ed63_body.asm）は、ページ 1 を RAM に切り替えて ED 63 / 6B を実行し、
  6363h・(nn)・HL の変化を表示する診断 ROM。
- ED 63 / ED 6B / ED 71 の実機の動作は [r800_undocumented.md](./r800_undocumented.md) にまとめてある。
- ED 71 の診断 ROM は ed71_test.rom（Z80 と R800 の比較）、ed71b_test.rom（R800 で A・B・C・F を変えた 9 ケース）、
  ed71c_test.rom（オペランドの出どころ）、ed71d_test.rom（置き換えが起きる確率）。

## Z80 の扱い
- SCF/CCF の X/Y は（Q レジスタ依存のため）比較しない。
- OUT (C),0 は CMOS Z80（turbo R の T9769 内蔵）の動作として FFh の出力を期待する。

## 検証状況
- openMSX: Panasonic FS-A1GT で 3586 項目すべて ERR 0（エミュレータ上で約 5 分）。
  Panasonic FS-A1WSX で Z80 の 1802 項目が ERR 0。
- z80test 追加後（4184 項目）の openMSX FS-A1GT: ERR 129（エミュレータ上で約 19 分）。R800 は全項目 OK。
  NG はすべて openMSX の Z80 の簡略化によるもの。
  - `Q` の 120 件余りと `ZT SCF/CCF` 系 4 件: openMSX は SCF/CCF の X/Y を (F or A) としている。
  - `WZ INIR/INDR->NOP'`: openMSX はリピート中の MEMPTR を BC + 1 としている。
  - `ZT LDIR/LDDR/INIR/INDR->NOP'` は `=OLD` の注記になる。
