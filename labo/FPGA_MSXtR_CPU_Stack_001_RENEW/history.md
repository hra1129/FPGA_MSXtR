# 作業履歴 (FPGA_MSXtR_CPU_Stack_000)

## 2026-09-03 作業の一区切り

実機 (Tang Nano 20K × 2 + Raspberry Pi Pico2W) での動作確認に向けて発生した
不具合の調査・修正を行い、電源投入時から VDP 画面出力まで 100% 動作する状態になった。

以下、時系列の概要をまとめる。

---

### 1. SPI 経由の BootROM / PPI 読み出しタイムアウト (0xAA/0xBB エラー)

**症状:** Pico から SPI で BootROM/PPI を読み出すとタイムアウトする。

**調査・対応:**
- Pico 側ファームウェアにデバッグ用コマンドを追加
  - `fpga_get_debug_signal()` (コマンド 0x0A): FPGA 内のパイプラインがどこまで進んだかを返す
  - `fpga_get_debug_test()` (コマンド 0x0B): 固定値 0xA5 返却によるパス疎通確認
- CPU ボード側に `debugger` モジュール (src/debugger/debugger.v) を新規追加。
  SPI→device→bootrom の各ステージのうち、最後に完了したステージを
  優先度エンコードした値 (リセット直後=123, spi_valid&&spi_ready=1 〜 spi_rdata_en=6) を返す。
- `ip_spi.v` にコマンド 0x0A / 0x0B を実装。INTR 抑制フラグが CS 非アサート前に
  クリアされてしまうタイミング不具合を修正。
- `msx_slot` をバイパスした実験で、バイパス時は読み出しが成功することを確認し、
  問題が `msx_slot` モジュールにあることを切り分けた。

**結論:** `msx_slot.v` が従来 clk_42m / clk_215m の二重クロック設計であり、
CDC (クロックドメイン間) の不安定が根本原因と判断。**単一クロック (clk_42m) 設計へ全面改修**した。

---

### 2. msx_slot.v の単一クロック化と MSX バスサイクルタイミングの精密化

ユーザ提供の詳細なタイミングチャート (Tステート + クロックカウント指定) に基づき、
Memory / I-O / M1 各サイクルのスロット信号生成タイミングを全面的に見直した。
clk_42m = 42.95454MHz の 12 サイクル = 1 Tステート (Z80 3.579545MHz の 1 クロック期間)。

主な修正内容:

- **二重クロック (clk_215m) の撤廃**: 全て clk_42m 単一クロックで動作するよう改修
- **Tステート内タイミング定数の整理** (MSX 実機のタイミングチャート準拠):
  /MERQ, /IORQ, /RD, /WR, /SLTSL, /CS, /M1, /RFSH のアサート/リリース位置を
  T1〜T5 内のクロックカウントで指定する localparam 群に集約
- **slot_a アドレス出力の修正**: I/O サイクル中に ROM アドレスが出力されて
  アドレスが不安定になっていた問題を修正 (I/O 中は ff_bus_address を保持出力)
- **/IORQ のアサートタイミング修正**: T1 から T2 へ移動し、/WR (1カウント先行) との
  相対位置を実機タイミングに合わせた
- **slot_data_dir の極性確定**: ロジアナ実測により 1=Write(CPU→Slot), 0=Read(Slot→CPU)
  と確認し、`ff_slot_wdata_en` に直接接続 (反転なし)。以後変更禁止。
- **RFSH アサートタイミング修正**: T3 → T4 へ (3箇所)。/RFSH Low 期間は
  T4 → T5 にまたがる約 419ns (18 サイクル)
- **外部 /WAIT 中のカウンタ凍結漏れ修正**: `ff_t_state` のみ凍結で下位カウンタ
  `ff_slot_timing` が回り続けており、凍結中に T1/カウント11 の /MERQ 条件が
  周期的に再ヒットする不具合を修正 (`w_timing_hold` でカウンタ自体も凍結)
- **slot_clock_n の独立カウンタ化**: 実機では WAIT 中も 3.58MHz クロックは止まらないため、
  WAIT 凍結とは独立した自走カウンタ `ff_clock_gen_timing` で生成するよう分離
- **TW (Z80 WAIT ステート相当) の挿入位置修正 (最終修正)**:
  従来は TW が T2 開始直後 (`c_sig_sltsl_assert`=0) に発火し、/WR・/IORQ・/CS の
  アサート前にシーケンスを凍結していた。そのため /WR Low パルス幅が
  約 1.5 クロック (3.579545MHz 換算) しかなかった。
  TW 発火位置を I/O サイクルは `c_sig_iorq_assert`(=5)、M1 サイクルは
  `c_sig_cs_assert`(=1) へ変更し、各信号がアサート済みの状態で凍結・
  TW 中も Low を維持・T3 途中でリリースする正しい波形 (約 2.5 クロック ≈ 675ns) に修正。

**検証:**
- `src/msx_slot/test_001/` (単体テスト): リセット、クロックアイドル、デバイス即時/遅延読み出し、
  スロットフォールバック、メモリ読み出し、ROM マッピング、I/O アドレス安定性、
  I/O 読み書き (TW 検出含む)、M1 アクセス、外部 /WAIT、長時間 /WAIT、
  アイドルリフレッシュ × 2、high_speed_mode 各種 — 全項目 OK
- `src/test_001/` (Stack 統合テスト, SPI コマンド経由): PASS 7 / FAIL 0
  - BootROM 先頭 8 バイト読み出し、メモリ書き戻し、PPI Port A 書き戻し、
    空 I/O 読み書き完了、ROM 書き込み保護、VDP I/O アクセス (0x98-0x9C)

**注意 (テストベンチ):** I/O write テストでは「TW アクティブ待ちループ」を
/WR→/IORQ の順序チェックより先に置くと、待ちループが両信号のアサートを
追い越して "IORQ before WR" を誤検出する。正しい順序は
`wait_wr_n_checked()` → iorq_n==1 確認 → 1clk 進めて iorq_n==0 確認 → TW 確認。

---

### 3. Gowin EDA デバイス設定誤り (ユーザ発見・修正)

FPGA が類似の誤ったデバイス (GW2AR-18 と微妙に異なる設定) で合成されており、
実機でのテスト結果が不安定になっていたことをユーザが発見・修正。
これにより本不具合期間中の実機検証結果にはノイズが混じっていたことが判明した。

---

### 4. 電源投入直後に VDP 出力が出ない問題

**症状:** 電源投入後、VDP (HDMI) 出力が出ない。VDP ボードの DIPSW[0] を
一度 0→1 に切り替えてから初期化コマンドを再送すると表示が出る。

**調査:**
- VDP ボード (FPGA_MSXtR_VDP_Stack_000) 側の msx_slot.v は
  `w_io_address = (dipsw==0) ? 8'h88 : 8'h98` として I/O アドレスを切り替えるのみで、
  DIPSW 切り替え自体には内部状態を変える効果がないことを確認。
  つまり回復に効いていたのは DIPSW 切替ではなく初期化の再送の方。
- Pico 側起動シーケンスに根本原因を特定:
  - 修正前: `sleep_ms(5000)` → `fpga_msx_reset(false)` (リセット解除) → 即座に VDP 初期化
  - VDP ボードは slot_reset_n 解除後に SDRAM 初期化シーケンス (約 300µs) を実行する。
    その間、VDP 側 msx_slot は `ff_initial_busy=1` で I/O キャプチャを無効化し、
    /WAIT もアサートされる設計だったが、実機では /WAIT 延長が効かず (後述)、
    リセット解除直後に Pico が送った VDP 初期化コマンド (R#0, R#1, ...) が
    全て捨てられていた。表示 ON ビットを含む R#1 が届かないため画面は出ない。

**修正 (controller/FPGA_MSXtR_Stack_Controller_000/fpga_msxtr_controller.c):**
起動時の待機を `sleep_ms(5000)` から `sleep_ms(100)` に変更し、
**リセット解除後に待機が来るよう順序を整理**。
VDP ボードの SDRAM 初期化が完了してから VDP 初期化コマンドを送る構成にした。
この修正により、電源スイッチ ON で 100% 表示が出ることを実機確認済み。

**未解決の懸念:**
VDP ボードの SDRAM 初期化中は /WAIT がアサートされる設計のため、
本来であれば CPU ボード側のバスサイクルが約 300µs 延長され、初期化コマンドは
取りこぼされないはずだった。実機で /WAIT が効いていない点は不可解であり、
基板のミス (配線・接触不良) の可能性があるため、後日テスター等で調査予定。

---

### 関連ファイル一覧 (今回変更があった主なもの)

- labo/FPGA_MSXtR_CPU_Stack_000/src/msx_slot/msx_slot.v — 単一クロック化・タイミング全面修正
- labo/FPGA_MSXtR_CPU_Stack_000/src/msx_slot/test_001/tb.sv — リグレッションテスト拡充
- labo/FPGA_MSXtR_CPU_Stack_000/src/debugger/debugger.v — 新規追加
- labo/FPGA_MSXtR_CPU_Stack_000/src/spi/ip_spi.v — コマンド 0x0A/0x0B 追加、INTR 抑制修正
- labo/FPGA_MSXtR_CPU_Stack_000/src/FPGA_MSXtR_CPU_Stack.v — debugger 組み込み、バイパス撤去
- controller/FPGA_MSXtR_Stack_Controller_000/fpga_msxtr_controller.c — 起動シーケンス修正
- controller/FPGA_MSXtR_Stack_Controller_000/fpga_io.c/.h — デバッグコマンド追加

---

## 2026-09-12 作業履歴 (FPGA_MSXtR_CPU_Stack_001: CPU切替・バスプロトコル改修・診断機能拡張)

実機 (Tang Nano 20K × 2 + Raspberry Pi Pico2W) 上で turboR BIOS (msxtr.rom) を起動した際の
Z80 $\rightarrow$ R800 切替後の動作不具合の診断・原因究明、ならびにバス・CPU切替・SPI診断周りの
大規模な改修とテスト環境整備を実施した。

---

### 1. SPI デバッグ信号 (0x0A) の拡張とリカバリ安定化

**背景・目的:**
実機で Z80 / R800 がどこで停止・暴走しているかを正確に把握するため、診断情報の大幅拡張を実施。

**実装内容:**
- **SPI 応答フォーマット拡張**: 176bit (22byte) 診断信号 ＋ 末尾 `0xA5` 固定リンクチェックバイト (計 23byte)
- **FSM 異常リカバリの最優先化**: `ip_spi.v` で `spi_cs_n` 解除 (`1'b1`) を `!reset_n` 直後の最優先条件とし、どのステートからでも確実に `ST_IDLE` へ復帰可能にした。
- **Pico 側 4 キーダンプ機能の拡充** (`fpga_msxtr_controller.c`):
  - Z80 PC / R800 PC、現在のプロセッサモード (Z80/R800)
  - CPU 切替要求フラグ / 目標CPU / FSMステート / 切替要求回数 / モード遷移回数
  - Z80 / R800 各バスのアドレス、`valid`、`ready`、`active`、リセット状態
  - S2026 内部レジスタ状態 (index, rom_mode, switch, 各クロックイネーブル)
  - スロット選択状態 (A8h, SSL0, SSL3, 物理 `/SLTSL0..3`, `/CS1..12`, `BUSDIR`, 制御線, データ方向)
  - FFFFh への書込みトラップフラグ (`seen`, `is_39`, `by_r800`) およびその瞬間の R800 PC
  - 割り込みピン状態・エッジ回数・ACK回数、SPIリンクパターン (0xA5) 検証

---

### 2. CPU バスプロトコルの刷新と Z80 / R800 コアのバスハンドシェイク改修

**不具合事象:**
BootROM 内でサブルーチン CALL を実行した際、スタックへの戻りアドレス書き込みが欠落し、戻り先が不定になって暴走する現象が発生。

**原因:**
`cz80_inst.v` / `cr800_inst.v` が Z80 の raw タイミングピン（`ff_rd`, `ff_wr_n_i`）を擬似生成してバス要求を出していたため、要求受理 (`bus_ready`) と `bus_valid` のアサート期間が噛み合っていなかった。また、`OUT (n),A` 命令で `acc` の値が `bus_valid` より 1 サイクル遅れて出力されるスキューが存在していた。

**改修内容:**
- **バスハンドシェイクの正常化**:
  - `ff_bus_valid`, `ff_requested`, `ff_t_state_d` による「同一 T-state で 1 回のみ要求を発行し、書き込みは `bus_ready`、読み出しは `bus_rdata_en` を受けるまで `bus_valid` を保持し、完了まで CPU コアに Tw (Wait) を挿入する」方式へ全面改修。
  - Z80 側 (`cz80_inst.v`) および R800 側 (`cr800_inst.v`) の両方に同一仕様を適用。
- **`OUT (n),A` データスキュー解消**:
  - `cz80.v` および `cr800.v` に `w_do` を追加し、`OUT (n),A` 実行時は内部レジスタ `acc` を即座にデータバス出力ピンへバイパス出力するよう修正。

---

### 3. Slot Board 接続時のデータバス競合防止

**不具合事象:**
Slot Board 接続時、オンボード ROM (Main ROM / Sub ROM) や漢字 ROM の読み出しデータが不定値（化け）になる。

**原因:**
オンボード ROM 読み出し時にも外部スロットの `/SLTSL` や `/IORQ` がアサートされ、Slot Board 上のトランシーバ (U3) が外部バスデータを CPU 側へドライブして内部 ROM データと衝突していた。

**改修内容 (`msx_slot.v`):**
- オンボード ROM アクセス時 (`w_onboard_rom_access = 1`) は外部 `/SLTSL0..3` を非アサート (`1'b1`) に維持。
- 漢字 ROM アクセス時は外部 `/IORQ` を非アサート (`1'b1`) に維持。
- オンボード ROM アクセス時は `slot_data_dir = 1'b1` (CPU $\rightarrow$ Slot 方向) に固定し、外部トランシーバからの逆流ドライブを遮断。

---

### 4. S2026 の CPU 切替機構の確立と単体・結合テストの構築

**仕様確認:**
- turboR では Z80 と R800 は独立した CPU コアであり、レジスタコピー等は行わない。
- 各 CPU は非選択時に `enable = 0` となり内部状態（PC を含む全レジスタ）をそのまま保持する。再選択時は以前停止した位置から即座に再開する。
- 共有バスは選択中 CPU のみが排他的に使用し、非選択 CPU への `ready` や `rdata_en` はマスクされる。

**テスト環境構築:**
- **`src/s2026/test_001`**: S2026 単体での CPU 切替・状態保持・バス MUX テストに置換（PASS = 23, FAIL = 0）。
- **`src/test_003` (新規作成)**:
  - `src/bootrom` をコピーして独立させた専用 BootROM 環境を作成。
  - Z80 が BootROM (0000h) から起動 $\rightarrow$ UART 'Z' 出力 $\rightarrow$ スロット初期化 $\rightarrow$ S2026 で R800 へ切替 $\rightarrow$ R800 が 0000h から起動 $\rightarrow$ UART 'R' 出力 $\rightarrow$ S2026 で Z80 へ切り戻し $\rightarrow$ Z80 が停止位置から再開して UART 'B' 出力、という一連の切替ハンドシェイクを TOP 結合レベルで完全検証（PASS = 9, FAIL = 0）。

---

### 5. MSXturboR 実機ブートシーケンスの組み込み（R800 初期 DI フェッチ）

**背景:**
実機 turboR では、電源投入直後はまず R800 で 1 命令 (`0000h: DI`) をフェッチ・実行して R800 内部の割り込みを禁止 (IFF=0) にし、PC を `0001h` (`JP 126Bh`) に進めた状態で Z80 に切り替わってコールドブートが始まるという実機挙動が判明。

**改修内容 (`s2026_cpu_select.v`):**
- リセット解除直後は初期状態を R800 (`processor_mode = 0`) とし、R800 が `0000h` の `DI` 命令 (F3h) を実行完了するまでステップ制御。
- `DI` 実行完了（T3 で `inte_ff1/2 <= 0`、PC=`0001h`）後、自動的に `processor_mode <= 1` (Z80) へ遷移して Z80 を起動。

---

### 6. A7h ポート実装と SPI コマンド 11h による LED 状態送出

**仕様・実装:**
- I/O ポート A7h に `pause_led.v` を接続し、R800 LED / Pause LED 制御を実装。
- SPI コマンド `11h`（キーボード更新）のプロトコルを拡張:
  - 1 バイト目: コマンド `0x11`
  - 2 バイト目: FPGA から **LED 状態バイト** (`bit0: r800_led, bit1: pause_led, bit2: caps_led, bit3: kana_led`) を Pico へ返却
  - 3〜14 バイト目: Pico からキーマトリクス 12 バイトを受信
- Pico 側 (`fpga_msxtr_controller.c` / `fpga_io.c`) で取得した LED 状態を STM32 キーボードコントローラへ I2C 転送する経路を整備。
- `src/spi/test_002` にてコマンド 11h の LED 読み出し・マトリクス更新を検証（PASS = 63, FAIL = 0）。

---

### 関連ファイル一覧 (今回変更・追加したもの)

- labo/FPGA_MSXtR_CPU_Stack_001/src/spi/ip_spi.v — 23byteデバッグ信号、コマンド11h LED返却、CS解除最優先化
- labo/FPGA_MSXtR_CPU_Stack_001/src/cz80/cz80_inst.v, cz80.v — Z80 バスハンドシェイク正常化、OUT早期データ出力
- labo/FPGA_MSXtR_CPU_Stack_001/src/cr800/cr800_inst.v, cr800.v — R800 バスハンドシェイク正常化、OUT早期データ出力、PC出力
- labo/FPGA_MSXtR_CPU_Stack_001/src/s2026/s2026_cpu_select.v — 初回 R800 DI フェッチ付き CPU 切替ステートマシン
- labo/FPGA_MSXtR_CPU_Stack_001/src/s2026/s2026_register.v — `w_s2026_rdata` 8bit宣言、レジスタ6ハンドシェイク
- labo/FPGA_MSXtR_CPU_Stack_001/src/address_decode/address_decode.v — `s2026_cs`, `pause_led_cs` デコード適正化
- labo/FPGA_MSXtR_CPU_Stack_001/src/pause_led/pause_led.v — A7h Pause/R800 LEDポート
- labo/FPGA_MSXtR_CPU_Stack_001/src/msx_slot/msx_slot.v — オンボードROM/漢字ROM時の外部バス絶縁
- labo/FPGA_MSXtR_CPU_Stack_001/src/FPGA_MSXtR_CPU_Stack.v — デバッグ信号統合、FFFFh書込みトラップ、LED信号配線
- labo/FPGA_MSXtR_CPU_Stack_001/src/s2026/test_001/ — S2026 CPU切替単体テスト
- labo/FPGA_MSXtR_CPU_Stack_001/src/test_003/ — BootROM CPU切替統合テスト (新規)
- controller/FPGA_MSXtR_Stack_Controller_001/fpga_io.h, fpga_io.c — 23byteデバッグデコード、コマンド11h LED取得
- controller/FPGA_MSXtR_Stack_Controller_001/fpga_msxtr_controller.c — 4キーダンプ表示拡充、LED状態反映

---

## 2026-09-17 作業履歴 (FPGA_MSXtR_CPU_Stack_001_RENEW: CZ80 即値ロードの読み出しデータ保持)

### 症状

`LD A,82h` (opcode `3Eh`) を実行しても、CZ80 内部の A レジスタ `acc` に
即値 `82h` が取り込まれない。

### 原因

`cz80.v` では、メモリリードサイクルの完了後、次マシンサイクルの T1 で
登録済みの `read_to_reg_r` に従い `acc <= save_mux` を実行する。
このとき `save_mux` は `di` 入力を参照する。

一方、`cz80_inst.v` では次マシンサイクルの T1 冒頭で新しい `bus_valid` を
発行するため、同時に `ff_bus_rdata <= 8'hFF` で読み出しデータを初期化していた。
結果として、前マシンサイクルで取得した即値ではなく `FFh` が `di` に渡されていた。

### 修正

- `cz80_inst.v` に `ff_di` を追加。
- 各 T1 の開始 (`w_t_state == 3'd1`, `state_count == 4'd1`) で、初期化前の
  `ff_bus_rdata` を `ff_di` へ退避。
- `cz80` の `dinst` は従来どおり最新の `ff_bus_rdata` を接続し、命令フェッチの
  T2 デコードを維持。
- `di` は T1 中のみ `ff_di` を接続し、T2/T3 は従来どおり `ff_bus_rdata` を接続。
  これにより T1 で行う前サイクルの書き戻しは保持値を使いつつ、T2/T3 で即値・分岐
  オフセット・アドレス値を参照する既存動作を維持した。
- バス要求の発行タイミングおよび CPU の停止/Tw 挿入は変更していない。

### 検証

- `src/cz80/test_001/run.bat`: `DI; LD A,82h; JP loop` の回帰を追加し、
  `acc=82` を確認。
- `src/test_002/run.bat`: コンパイルエラー・警告なし、`All tests PASSED`。

### 関連ファイル

- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cz80/cz80_inst.v — `ff_di` と T1 時の `di` 選択を追加
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cz80/test_001/test_program.asm — `LD A,82h` 回帰プログラム
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cz80/test_001/tb.sv — `acc == 8'h82` の検証を追加

---

## 2026-09-17 作業履歴 (S2026 CPU切替方式の刷新: busrq/busack廃止 → enableマスク方式)

### 背景・目的

実機で Pico のシリアル通信に "fpga timeout" が出て停止する不具合の調査から着手。
調査の結果、CPU切替(Z80/R800/Pico)の従来方式が、Z80/R800コア内蔵の BUSREQ/BUSACK
機構と `s2026_cpu_select.v` の busak待ちに依存しており、コア内部のFSM不具合と
絡んで切替がハングしうる構造だと判明。CPU速度安定化のための大改修(cz80_inst.v の
バスハンドシェイク刷新)は必要な変更だったため維持しつつ、CPU切替の仕組み自体を
より単純で検証しやすい方式に置き換えることにした。

### 新方式

- busrq_n/busak_n によるハンドシェイクを廃止し、各コアが **M1サイクル開始
  (`w_t_state==1, w_m1_n==0, state_count==1`)** で `run_req` を取り込んで自らの
  `cen` をマスクする方式に変更 (`cz80_inst.v`, `cr800_inst.v`)。
- Pico側 (`cmcu.v`) は **バスアイドル(`!ff_running`)** の瞬間に `run_req` を
  取り込む方式とし、非オーナー時は新規バスサイクルを一切受理しない
  (`mcu_ready` を `ff_run` でゲート)。
- `s2026_cpu_select.v` は、切替時に z80/r800/pico 全員の `run_req` を落とし、
  3者全ての `run_ack` が0(=全員停止)になるのを待ってから切替先のみを
  再稼働させる方式 (`w_all_stopped` 待ち) に変更。
- ついでに見つけた副次バグ修正: `s2026_cpu_select.v` の `sys_reset_n` リセットで
  `ff_cpu_sel[1]` が誤って`1'b1`(Pico選択状態)にリセットされ、reset直後に
  Z80が一切走らなくなるバグを `1'b0` に修正。

### cr800_inst.v の最新化

`cr800_inst.v` が `cz80_inst.v` の旧版(タイミング調整・`bus_valid` FSM刷新・
`ff_di`機構が入る前の状態)のまま放置されていたため、`cz80_inst.v` の最新実装を
ベースに全面更新(識別子のリネームのみで実質同一ロジックに統一)。
`git diff --no-index` で命名以外の差分が無いことを確認。

### 検証

- `src/cz80/test_001`, `src/cmcu/test_001`, `src/s2026/test_001`: 全てPASS。
- `src/test_002`: PASS(BootROM無効化・CPU起動シーケンスとも正常動作を確認)。
- `src/test_003`: 相変わらず FAIL。ただし原因は今回のCPU切替方式変更とは無関係で、
  以前から存在する `cz80_inst.v`/`cr800_inst.v` の `bus_valid`/`bus_ready` FSM
  (コミット 7a9ae3b/5c45712 で導入されたタイムアウト処理まわり)に起因すると
  切り分け済み。cr800側にも同じFSMを適用したため、同じ症状がR800側にも
  伝播している。

### 未解決 / 次回への申し送り

- `cz80_inst.v`/`cr800_inst.v` の `bus_valid` FSM (T-state/state_countの
  固定タイミングで無条件に `bus_valid` を打ち切る/タイムアウトする処理) に
  何らかの不整合があり、`test_003` (CPU切替を伴う結合テスト) で
  `mode_cnt` が異常増加し、Z80が `BootROM` 実行中の早い段階で停止する。
  次回はここを最優先で調査・修正すること。修正時は cz80/cr800 両方に
  同じ修正を適用する。
- 実機の "fpga timeout" も、上記 `bus_valid` FSM 不具合によりCPUがバスサイクル
  途中で固まり、`run_ack` が落ちずCPU切替(バス所有権切替)がタイムアウトする、
  という説明が最も有力。

### 関連ファイル

- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cz80/cz80_inst.v, cr800/cr800_inst.v — busrq/busack廃止、run_req/run_ack方式、cr800側の全面最新化
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cmcu/cmcu.v — run_req/run_ack方式、バスアイドル時ラッチ
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/s2026/s2026_cpu_select.v, s2026.v — w_all_stopped方式への刷新、reset初期値バグ修正
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/FPGA_MSXtR_CPU_Stack.v — 上記に伴う配線名変更
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cz80/test_001/tb.sv, cmcu/test_001/tb.sv, s2026/test_001/tb.sv — run_req/run_ack名への追随、s2026 test_001のreset配線修正

---

## 2026-09-18 朝 作業履歴 (初期SPI確認・Pico初期バス所有権・VDP未表示調査)

### 1. test_002 の初期SPIシーケンスをPicoファーム互換化

固定時間待ちだった `src/test_002/tb.sv` の起動処理を、実機Picoファームと同じ
SPIコマンドによる確認へ変更した。

- コマンド `FFh` を送り、応答 `64h` を受信するまで接続確認を再試行する
  `spi_wait_fpga_ready` を追加。
- 接続確認直後にコマンド `05h` を送り、status bit0がREADYになるまで確認する
  `spi_wait_ready` を追加。最大30回すべてBUSYの場合は `FPGA Timeout.` を表示して
  `$stop` する。
- ModelSimでは接続確認、READY確認ともに1回目で成功した。READY応答は `04h` で、
  bit0はREADY、bit2のみSerial SRAM初期化中を示していた。
- `src/test_002/run.bat`: コンパイルエラー・警告なし、`All tests PASSED`。

実機で発生していた `FPGA Timeout.` は、PicoファームをPico起動モードへ切り替えて
リビルドした後は発生しなくなった。

### 2. SPIデバッグ信号フォーマットのRENEW版への追随

RENEW版 `ip_spi.v` は、旧版の診断22byte＋リンクパターン1byteではなく、
`debug_signal[157:0]` を160bitへゼロ拡張した20byte＋リンクパターン`A5h`の
計21byteを返す。Pico側が旧23byte形式のまま読み出していたため整合させた。

- `fpga_get_debug_signal()` の受信長を23byteから21byteへ変更。
- 158bit信号は途中からbyte境界に揃わないため、bit offsetとbit widthを指定して
  展開する `fpga_debug_get_bits()` を追加。
- RENEW版で削除されたCPU切替要求回数、切替FSM状態、S2026レジスタ状態を
  `fpga_debug_signal_t` と表示から削除。
- 残存する3.579MHz pulse、21MHz clockを `clock_status` として表示。
- `src/test_002/tb.sv` のデバッグ読出し長も21byteへ変更。
- PicoファームのWSLビルド、および `src/test_002/run.bat` はともに成功。

### 3. FPGAリセット直後のPicoバス所有権を修正

Pico起動モードであるにもかかわらず、4キーのデバッグ表示でZ80 PCが進行していた。
原因は `s2026_cpu_select.v` の `sys_reset_n` リセット時に
`ff_cpu_sel[1] <= 1'b0` としており、初期状態が `cpu_sel=00` (Z80所有)に
なっていたことだった。

仕様はFPGA起動直後からPicoがバスを所有することであり、初期値を
`ff_cpu_sel[1] <= 1'b1`、`ff_target_sel[1] <= 1'b1` に修正した。
これにより初期状態は `cpu_sel=10` (Pico所有、戻り先Z80)となる。

実機のデバッグ表示で以下を確認した。

- Z80 PC、R800 PCともに `0000h` のまま変化しない。
- `z80_active=0`、`r800_active=0` で、両CPUが停止している。
- `link_pattern=A5h` でSPI診断通信は正常。

前日の履歴にある「`ff_cpu_sel[1]=1` がバグなので0へ修正」という記述は誤り。
Pico初期所有が本来の仕様であり、`ff_cpu_sel[1]=1` が正しい。

なお、Pico側デバッグ表示のprocessor modeはRTLの極性
(`0: Z80, 1: R800`)と逆に表示されており、現在の `mode=R800` 表示は実際には
「戻り先Z80」を意味する。表示修正は未実施。

### 4. 未解決: PicoからのVDP初期化が認識されず黒画面

Picoがバスを所有し、`vdp_set_screen1()`、`vdp_set_screen1_font()`、
`vdp_set_screen1_message()` を実行しているにもかかわらず、VDP画面は黒いまま。

CPU切替・スロット信号改修前は、同じPico所有モードとPicoファームによる
VDP初期化で正常に表示できていた。そのため、今回の不具合を誤動作していたZ80の
VDP初期化が隠していたとする仮説は否定される。VDPは物理的に別FPGAでCPU切替を
認識しないため、CPU Board側のスロット信号改修が最有力原因である。

VDP Stack側 (`labo/FPGA_MSXtR_VDP_Stack_001/src/msx_slot/msx_slot.v`) は、
`slot_iorq_n` と `slot_wr_n` / `slot_rd_n` を85MHzで2段同期し、両方Lowの期間を
I/Oアクセスとして検出する。次回はPicoからポート`98h`/`99h`へ書いた際の以下を
優先して確認する。

- `slot_iorq_n` と `slot_wr_n` が同時に十分な期間Lowになるか。
- Low期間中に `slot_a[7:0]` が `98h`/`99h`で安定しているか。
- `slot_d[7:0]` にPicoの書込みデータが正しく出ているか。
- `slot_data_dir` の極性と実基板のバストランシーバ方向が一致しているか。
- VDP Stack側で `ff_iorq_wr`、`bus_valid` が立ち、VDPコアへ書込みが届くか。

`slot_clock_n` はVDP Stack側が参照していないため、今回の調査対象外とする。

### 今朝の関連ファイル

- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/test_002/tb.sv — FFh/64h接続確認、05h READY確認、21byteデバッグ読出し
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/s2026/s2026_cpu_select.v — リセット直後のPicoバス所有を復元
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/spi/ip_spi.v — RENEW版21byteデバッグ応答の確認対象
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/msx_slot/msx_slot.v — 次回のPicoスロット波形調査対象
- labo/FPGA_MSXtR_VDP_Stack_001/src/msx_slot/msx_slot.v — 次回のVDP側I/O受信確認対象
- controller/FPGA_MSXtR_Stack_Controller_001/fpga_io.h, fpga_io.c — 21byteデバッグ形式へ追随
- controller/FPGA_MSXtR_Stack_Controller_001/fpga_msxtr_controller.c — デバッグ表示更新、VDP初期化シーケンス確認対象

---

## 2026-09-18 夜 作業履歴 (S2026 polarity / stop freeze / refresh priority / VDP write-drop 連鎖調査)

### 1. processor_mode の極性ミスマッチを修正

症状として、CPU 切替の対象指定は見かけ上正しく見えても、実際の `ff_cpu_sel[0]` と
`processor_mode` の極性が逆になっており、R800/Z80 の選択判定が反転していた。

原因は、S2026 側の外部仕様では `processor_mode=0` が R800、`1` が Z80 である一方、
内部の `ff_cpu_sel[0]` がそのまま使われていたため、境界で反転されていた点だった。

修正方針:
- S2026 外部仕様と内部選択状態を明確に分離
- 切替要求の境界で `cpu_change_target` の極性を正しく変換して受け取り
- `s2026_cpu_select.v` / `s2026_register.v` の扱いを整合させる

これにより、Pico -> Z80 / Z80 -> Pico のシーケンスが仕様どおりに見えるようになった。

### 2. 停止時に出力がマスクされるだけでなく内部状態も固定するよう修正

不具合調査の途中で、CPU が止まっているときに `ff_run` が 0 でも各コアの内部信号が
まだ変化し続けているケースがあることが分かった。

これは単に `out` の極性を隠すだけでは不十分で、停止中に内部制御FFが変化してしまうと
再開時の符号・FSM 状態が破綻しうるため、`cz80_inst.v` および `cr800_inst.v` で
`!ff_run` 時に内部生成信号を保持する方式へ変更した。

修正内容:
- `ff_run == 0` のときは `bus_valid`, `m1_n`, `rd_n`, `wr_n` 等の生成を維持
- 停止中に `ff_bus_valid` や内部制御が勝手に更新されないよう凍結
- 再開と同時に不正な立ち上がりや空のバス要求が発生しないように整理

これで「止まっている間の内部状態が動いてしまう」問題を潰した。

### 3. auto refresh と Pico の外部 I/O write の競合を修正

次に、Pico から VDP へ I/O 書込みを行うタイミングで、
自動 refresh が同時に立ち上がると要求が取りこぼされる不具合を再現した。

根本原因:
- `cmcu.v` 側で refresh の開始タイミングが T1 境界と一致しない場合に、
  その瞬間に Pico の `mcu_valid` が潰されるケースがあった
- refresh と `mcu_valid` が同時に発生したときに、優先順が不明瞭だった

修正内容:
- refresh は T1 境界でのみ発火するように制限
- refresh の開始時刻がずれている場合は待ってから開始
- `mcu_valid` と refresh が同時に来たら、Pico の I/O write を優先
- refresh 中は `mcu_ready` を 0 にして、要求が一時的に吸収されないように整理

これにより `cmcu/test_001` と `src/test_002` の再現テストで落ちなくなった。

### 4. 再現テスト追加

`src/test_002/tb.sv` に、Pico による VDP I/O write と refresh の同時発生を再現する
回帰テストを追加した。

テストの意図:
- CPU を Pico 所有に移す
- refresh が発火するタイミングを狙う
- 一方で VDP の `98h`/`9Ch` 系 I/O 書込みが発生する
- write が取りこぼされないことを確認する

結果:
- 修正前に再現していた症状が再現テストで観測される
- 修正後は `PASS = 1, FAIL = 0` で回帰が収まる

### 5. まだ残る可能性: SPI CS / accept レース

上記の refresh 修正で再現テスト自体は解消したが、実機ではまだ一部の VDP I/O write が
取りこぼされているように見える。ここからは、refresh だけではなく、
Pico の SPI コマンド到達と `cmcu` / `ip_spi` の受理タイミングの競合が残っている可能性が高い。

特に懸念される箇所:
- `ip_spi.v` で `ff_bus_valid` を落とすタイミング
- SPI CS の解除が `cmcu` の受理ウィンドウより早い場合の request drop
- `98h`/`9Ch` 系の外部 slot write で、要求受理前に CS が切れる問題
- `cmcu.v` の `mcu_ready` / `run_req` / `run_ack` の成立条件の境界

つまり、"refresh による消失" を潰した後も、"要求の受理が完了する前にリセット/CS解除されたことによる消失" が
実機で残っている可能性がある。次回はここを重点的に確認する。

### 6. 現時点の整理

- CPU 切替の極性ミスは修正済み
- 停止中の内部制御FFが動き続ける問題は修正済み
- refresh と Pico write の競合は修正済み
- 実機での VDP write 取りこぼしは、refresh 以外の受理レースがまだ残っている可能性が高い
- 次回は `ip_spi.v` / `cmcu.v` / slot write の受理境界を中心に確認予定

ここで本日の調査は一区切りとし、続きは明日以降に再開する。

---

### 最終メモ

今日は、CPU切替の極性整理、停止時の内部信号凍結、refresh と Pico I/O write の競合修正までを
一通りまとめた。実機の VDP 書込み取りこぼしは残っているが、その原因は refresh ではなく
SPI/CS受理タイミングのレースに近いと判断している。次回はこの境界を実測と再現で確認する。

---

## 2026-09-19 作業履歴 (Pico VDP write受理・SPI完了通知・バス所有権切替検証)

### 1. Pico経路のVDP write測定をtest_002へ追加

CPUコアが生成するslot信号を測定していた`test_003`では、PicoからのI/O write経路を
直接検証できていないことが判明した。そのため、Picoがバスを所有する`test_002`へ、
`01h, 98h, data`形式のSPI I/O writeを1000回送るテストを追加した。

データは`55h -> A5h -> AAh -> 5Ah`の順で循環させ、slot到達数、Low期間、データ保持、
データ系列を測定した。Pico経路でもslot信号幅とデータ保持は正常に見える一方、実機波形では
一定周期でアクセスが欠落することが確認された。

### 2. `cmcu`受理タイミングの特定

`cmcu.v`は`state_count == 0`かつ`!ff_running`のタイミングでのみ`mcu_ready`を出す。
42.95454MHzクロック上で12クロックに1回だけ受理可能な期間がある。

`ip_spi.v`はSPIでコマンド・アドレス・データを受信すると`bus_valid`を出すが、CSn解除を
受けると`bus_valid`を解除する。このため受理タイミングに一致しなかった要求が取り消され、
一定周期でwriteが欠落していた。

### 3. SPI_INTR完了通知方式の整理

Pico側のI/O・メモリ書込みについて、SPI送信後の固定待機だけでなく`SPI_INTR`を待ってから
CSnをHにする方式を試した。その過程で、`SPI_INTR`には次の2種類の意味があることを整理した。

- FPGA内部の要求受理完了通知 (`bus_valid && bus_ready`)
- FPGAからPicoへ送るデータの送信準備通知 (`spi_tx_load_en`)

`01h`/`03h` writeでは前者、`02h`/`04h`/`0Eh` readやstatus/debug等では後者を使う必要がある。
この仕様を`src/spi/readme.md`へ追記した。

### 4. バス所有権切替のtest_003検証

`test_003`へ、CPU実行中にPicoへバス所有権を移し、Z80/R800双方の`run_ack`とactive信号が0に
なること、Pico所有中にZ80 PCが停止すること、CPUへ戻した後に停止位置からZ80が再開することを
確認するテストを追加した。

結果はコンパイルエラー・警告なし、`PASS = 19`, `FAIL = 0`。SPI_INTRによるバス所有権変更通知で、
シミュレーション上のハングは再現しなかった。

### 5. Pico側のバス所有者管理を`fpga_io`へ集約

`fpga_io.c`に現在のバス所有者を保持するstatic変数を追加した。

- `0`: Pico所有
- `1`: CPU所有

`fpga_get_bus_owner()`を追加し、`fpga_set_bus_owner()`成功時に所有者状態を更新するようにした。
Pico所有でない場合のアクセスは次のように制限した。

- `fpga_outport()` / `fpga_poke()`: 何もせず終了
- `fpga_inport()` / `fpga_peek()`: `0xAA`を返す

コントローラ側の重複していた`pico_bus_owner`変数は削除した。WSLのbuild直下で`make -j`を
実行し、エラー・警告なしでビルド成功した。

### 現時点の整理と次回への申し送り

- refresh競合は修正済みで、Pico経路のslot波形幅・データ保持テストも通過した。
- `SPI_INTR`はコマンドによって「受理完了」と「送信準備完了」の2種類に分けて扱う必要がある。
- 最新の`ip_spi.v`は書込み時に`bus_ready`で通知する方向へ整理されているため、次回はtest_002の
  SPI_INTR波形と書込み受理数を再確認する。
- バス所有権の停止・復帰シーケンスはtest_003で`PASS = 19`, `FAIL = 0`まで確認済み。

本日の作業はここで一区切りとし、続きは次回に再開する。

---

## 2026-09-20 作業履歴 (cR800同期化・カートリッジバス競合調査・Z80 VRAM read不具合)

### 1. cR800ラッパーをcZ80の最新構造へ同期

Z80およびCMCUのタイミング調整後、未メンテナンスだった`cr800_inst.v`を
`cz80_inst.v`と比較した。CPU固有名を除いた内部バスラッパーに旧実装が残っていたため、
以下をcZ80側へ統一した。

- memory/I/O write要求の開始タイミング
- readタイムアウト処理と定数名
- `ff_bus_wdata`のリセット初期値
- 内部bus valid/ready FSMの構造

コメント・空白・CPU名を除外した正規化比較で論理構造が一致することを確認した。
`test_003`ではR800切替、Pico停止・CPU復帰、VDP write 1000回を含めて
`PASS = 91`, `FAIL = 0`となった。

### 2. カートリッジスロット接続時のデータ競合対策を再調査

過去版では、外部カートリッジが未応答でHi-Zでも、スロットボード上のバッファを通ると
HとしてCPU側へ戻り、内部VDPやオンボードROMのreadデータと競合する問題があった。

旧`FPGA_MSXtR_CPU_Stack_001`の実装を参照し、以下の信号による隔離条件を現行構成へ
移植する試行を行った。

- `slot_data_dir`
- `slot_iorq_n` / `slot_merq_n`
- `slot_sltsl0_n`〜`slot_sltsl3_n`
- `slot_cs1_n` / `slot_cs2_n` / `slot_cs12_n`

当初は`internal_device_cs`を新設し、PPI、SSRAM、BootROM等の内部デバイスアクセスを
外部スロットから遮断した。しかし実機ではスロットボード未接続でも、PicoからZ80へ
切り替えた後にMSX-BASICが起動しなくなった。

内部デバイスは外部スロットより先に応答する構造であり、通常の内部I/O・内部メモリまで
遮断する必要はないことが分かった。`internal_device_cs`による隔離は過剰であり、撤去した。

### 3. 要件を限定した隔離条件の検討

隔離対象は次の範囲に限定すべきと整理した。

- オンボードFlashROMおよび直接Flashアクセス時のメモリ系信号
- D8h〜DBhの漢字ROMアクセス時の`/IORQ`抑止
- 漢字ROMでは通常I/Oアドレスではなく、パラレルROM用19bitアドレスを`slot_a`へ出力
- 98h〜9ChのVDP readでは、VDPボードが`slot_data_dir`を介さず`slot_d`へ出力するため、
  カートリッジ側データ混入防止として`slot_data_dir`をwrite方向へ固定
- 通常の内部I/O・内部メモリではスロット信号を通す

この方針でRTLとテストを調整し、シミュレーションではCPU切替、Pico停止・復帰、
VDP write 1000回、外部VDPアクセス中のSLTSL/CS非アサートが通った。

### 4. 実機で発生したZ80暴走症状

実機へ書き込むと、Pico起動時の画面は正常だが、Z80へ切り替えた後に次の症状が発生した。

- 一度画面が水色になる
- 長時間後にBIOS画面とMSX-BASICが表示される
- 表示の一部が破損する
- 「け」に見える文字がBIOS画面中も連続して増殖する
- 画面スクロール付近で停止し、しばらくすると再びBIOS画面に見える状態へ戻る

単純なキーボード押下状態ではなく、Z80の命令fetch・スタック・I/O write等が化けて
暴走している可能性を検討した。また、`/IORQ`と`/WR`が不要に再発または保持され、
98hへの余計なwriteとしてVDPに認識されている可能性も候補とした。

### 5. 変更を撤回し、MSX-BASIC起動状態へ復帰

カートリッジ隔離関連の変更をいったん戻した。その結果、カートリッジスロットボードを
取り外した状態でMSX-BASICが起動する状態へ復帰した。

この状態で追加確認したところ、Z80からのVRAM readが失敗しているように見えることが判明した。
現時点では、Z80側のVDP readサイクル、`slot_data_dir`、`slot_d`、readデータ取り込みタイミングの
いずれに問題があるかは未確定。

### 次回への申し送り

次回はZ80からのVRAM read解析を最優先とする。

- `IN`命令時の`z80_iorq_n` / `z80_rd_n`タイミング
- `slot_iorq_n` / `slot_rd_n`と98h〜9Chアドレスの安定期間
- VDP側のデータ出力開始タイミング
- `slot_data_dir`の方向
- `slot_d`から`ff_bus_rdata`、`ff_di`へ取り込むタイミング
- 内部`bus_ready` / `bus_rdata_en`との競合

本日の作業はここまでとし、続きは次回に再開する。

---

## 2026-09-21 作業履歴 (Z80/Pico VRAM read不具合の原因特定と解決)

前回からの継続課題であった、Pico経由のVDP VRAM read/write比較テスト失敗について調査し、
実機で `VRAM read/write test OK (2048 bytes)` が連続して得られる状態まで解決した。

### 1. Pico側VRAM read/write比較テストの追加と初期症状

Picoファームウェア側で、不要になったFlashROMアドレスreadテストを撤去し、8キー押下時に
VDP VRAM read/write比較テストを実行するよう変更した。

テスト内容は、SCREEN1用フォントデータをVRAM 0000hから2048バイト書き込み、同じ範囲を
読み戻して期待値と比較するもの。

実機では当初、次のように大量のミスマッチが発生した。

- `VRAM read/write test NG (1357 mismatches / 2048 bytes)`
- 後続の診断パッチ入りでは `1358 mismatches / 2048 bytes`
- `actual` は主に `0x00`, `0x01`, `0x10`, `0x11`
- `expected` と比較すると bit4 / bit0 だけが一致し、それ以外のbitは0に落ちる傾向が強かった

例:

- `expected 0x1F, actual 0x11`
- `expected 0xF0, actual 0x10`
- `expected 0x81, actual 0x01`
- `expected 0x42, actual 0x00`

このパターンから、VDPコア内部のランダムなread不良ではなく、データバスのHigh側駆動に
bit依存の問題がある可能性が高いと判断した。

### 2. VDP Stack全体のModelSimテストベンチ作成

`labo/FPGA_MSXtR_VDP_Stack_001/src/test_001/` に、VDP Stack全体を動かすModelSim用
テストベンチを作成した。

主な内容:

- `FPGA_MSXtR_VDP_Stack` トップをDUTとしてインスタンス
- Gowin IP (`Gowin_rPLL`, `Gowin_rPLL2`, `Gowin_CLKDIV`) のシミュレーション用ダミーを作成
- 暗号化DVI IP (`DVI_TX_Top`) の最小スタブを作成
- SDRAMモデル `MT48LC2M32B2.v` を `sdram/test001/` からコピーして使用
- SCREEN1相当のVDPレジスタ初期化後、VRAMへ10バイトwrite/readを10回繰り返す
- CPU Stack側のI/Oサイクルに近い `/IORQ`, `/RD`, `/WR` タイミングでslot信号を駆動

シミュレーション結果:

- `VRAM write/read test OK (100 bytes)`
- `bus_rdata_en` からCPUサンプル相当点までの余裕は最小約291ns、最大約430.7ns

この結果から、少なくともシミュレーション上はVDPコア・SDRAM・VDP Stack側msx_slotの
VRAM read/writeデータパスは成立しており、単純な内部論理不具合ではなさそうだと判断した。

### 3. CPU Stack側cmcuの/RD延長診断

CPU Stack側 `cmcu.v` のI/O readで、`slot_d` のラッチが早すぎる可能性を切り分けるため、
診断用にI/O readのみ次の変更を一時適用した。

- `/RD` と `/IORQ` の立上りを `T3 state_count=11` から `T4 state_count=11` へ延長
- `bus_rdata_en` が来ない場合の `slot_d` フォールバックラッチを `T3 state_count=10` から
  `T4 state_count=10` へ遅延
- `bus_rdata_en` 経路はマスクせず、そのまま残した

実機結果はほぼ変わらず、むしろミスマッチが1件増えた。
このため「CPU Stack側cmcuがslot_dを早く取り込みすぎている」仮説は棄却した。

OpenDrain問題解決後、この診断パッチは不要な変更として完全に撤回した。
撤回後、`cmcu.v` 単体のModelSim `vlog` はエラー/警告なしで通過した。

### 4. VDP Stack側slot_dのOpenDrain設定が根本原因

VDP Stack側制約ファイル `FPGA_MSXtR_VDP_Stack.cst` を確認したところ、`slot_d[7:0]` が
全bit `OPEN_DRAIN=ON` になっていた。

OpenDrainではFPGAが0を強く駆動できる一方、1は能動駆動されずHi-Zとなる。
そのためDrive strengthを8から24へ上げても、High側の駆動能力は改善しない。
今回の `actual = expected & 8'h11` に近い実機ログは、この設定とよく一致する。

ユーザがVDP Stack側のOpenDrainをOFFに変更して実機確認したところ、結果は大幅に改善した。

一時的には、CPU Stack側cmcuの/RD延長診断パッチが残った状態で、先頭1バイトのみ
`expected 0x00, actual 0xAA` となった。

その後、CPU Stack側cmcuの/RD延長診断パッチを元に戻し、VDP Stack側OpenDrain OFFのみの状態で
再確認したところ、次のように完全一致した。

```text
VRAM read/write test start
VRAM read/write test OK (2048 bytes)
```

このOKが9回連続で得られた。

### 5. 最終結論

今回のVRAM read大量ミスマッチの主因は、VDP Stack側 `slot_d[7:0]` のCST制約が
`OPEN_DRAIN=ON` になっていたこと。

これによりVDP Stack側がVRAM readデータを外部slot_dへ出す際、Highを能動駆動できず、
CPU Stack側からはD4/D0以外のHighが0として読まれていた。

CPU Stack側cmcuの/RDラッチタイミングは原因ではなかった。
診断用に入れた/RD延長パッチは撤回済み。

### 関連ファイル

- controller/FPGA_MSXtR_Stack_Controller_001/vdp_control.c/.h — VRAM read/write比較テスト追加
- controller/FPGA_MSXtR_Stack_Controller_001/fpga_msxtr_controller.c — 8キー処理をVRAM read/writeテストへ変更
- labo/FPGA_MSXtR_VDP_Stack_001/src/test_001/ — VDP Stack全体ModelSimテストベンチ追加
- labo/FPGA_MSXtR_VDP_Stack_001/src/FPGA_MSXtR_VDP_Stack.cst — `slot_d[7:0]` のOpenDrain設定が根本原因
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cmcu/cmcu.v — /RD延長診断パッチを一時適用後、撤回済み

ここで一度GitHubへpush済み。作業は一区切りとする。

---

## 2026-09-21 作業履歴 (Cartridge Slot Stack試作基板向けバス競合対策とスロットマップ整理)

VDP VRAM read/write不具合解決後、Cartridge Slot Stack試作基板接続時のデータバス競合対策を再開した。

### 1. 試作Cartridge Slot Stackの制約と方針

Cartridge Slot Stack上のSN74LVC8T245は、D[7:0]をHigh/Lowで能動駆動する。
このD[7:0]はVDP Stack側D[7:0]とも共有されるため、I/O read時にCartridge Slot Stack側がCPU Stackへ返す方向になると、
VDP等のI/O応答とバス競合を起こす。

試作基板ではI/Oカートリッジを搭載しない運用ルールとし、I/Oカートリッジ対応は将来の基板修正で行う方針にした。

このため、現行試作基板向けには次のルールを採用する。

- I/O accessではread/writeを問わず、`slot_data_dir`をCPU Stack→Cartridge Slot Stack方向へ固定する。
- 外部カートリッジからCPU Stackへ返してよいのは、Slot1/Slot2のメモリreadのみ。
- Slot0/Slot3の内蔵FlashROM、Slot3-0のSSRAM、DirectFlash、I/O accessでは、Cartridge Slot Stack側からCPU Stackへ返させない。

### 2. 通常スロットアクセスとDirectAccessの理解を整理

Pico / Z80 / R800の通常スロット空間アクセスは、すべて同じMSX 64KB空間として扱う。

- 通常アクセスでは `A[15:0]` と `primary_slot` / `secondary_slot0` / `secondary_slot3` に従ってデコードする。
- `A[19:16]` を含む20bit FlashROM物理アドレスは、`flash_en` によるDirectAccess時だけ使用する。
- `dump_slot0()` はFlashROM direct readの確認ではなく、PicoがZ80のフリをして通常スロット経由でROMマップを読むテストである。

スロットマップの理解を以下に整理した。

- Slot0 page0/page1のROMマップ対象領域はFlashROM0へマップする。
- Slot0 page2/page3は未接続であり、page0/page1のミラーではない。
- Slot3-1はFlashROM0へマップする。
- Slot3-2のDiskROM pageはFlashROM0へマップする。
- Slot3-0はFlashROMではなくMemoryMapper / SerialSRAMへマップする。
- Slot1/Slot2は外部Cartridge Slot Stackのメモリアクセス対象とする。

### 3. msx_slot.v の修正

`slot_data_dir`の生成を見直し、外部Slot1/Slot2のメモリread時だけCartridge Slot Stack→CPU Stack方向を許可するようにした。

```verilog
assign w_external_memory_read = ~w_slot_rd_n & ~w_bus_io & ~w_flash_en & ((w_primary_slot == 2'd1) | (w_primary_slot == 2'd2));
assign slot_data_dir = ~w_external_memory_read;
```

これにより、次のアクセスではCartridge Slot Stack側からCPU Stackへ返さない。

- I/O read/write
- Slot0/Slot3の内蔵FlashROM read
- Slot3-0のSSRAM read
- FlashROM DirectAccess
- 漢字ROM read

また、JIS2漢字ROM read時のアドレス自動インクリメント条件がJIS1と異なっていたため、JIS2 readでもインクリメントされるよう修正した。

### 4. address_decode.v の確認

`address_decode.v` は、Slot3-0をMemoryMapper / SerialSRAM対象として扱う構造になっていることを確認した。

- `access_primary_slot == 3` かつ `access_secondary_slot3 == 0` で `slot3_0_selected` が成立
- `ssram_cs = slot3_0_selected & ~device_io & (device_address != 16'hFFFF)`
- `w_ssram_address = { w_mapper_segment, w_device_address[13:0] }`

このため、Slot3-0のSSRAMマップ理解と実装は一致していた。

### 5. テストとドキュメント更新

`src/msx_slot/test_001/tb.sv` を更新した。

- I/O read時に `slot_data_dir == 1'b1` となることを確認
- Slot1/Slot2のメモリreadだけ `slot_data_dir == 1'b0` となることを確認
- Slot0内蔵ROM、Slot3-1内蔵ROM、Slot3-0 SRAM、DirectFlash readでは `slot_data_dir == 1'b1` となることを確認
- Slot0 page2は未接続として、ROMも外部CSも出さない期待値へ整理
- Slot3-0 page2はMemoryMapper / SerialSRAM側で扱うため、`msx_slot`単体ではROMも外部CSも出さない期待値へ整理

`src/msx_slot/readme.md` も更新した。

- Slot0 page2/page3は未接続でありミラーではないことを明記
- Slot3-0はMemoryMapper / SerialSRAMにマップされることを明記
- 試作Cartridge Slot StackではI/Oカートリッジを暫定非対応とし、I/O access中はCPU Stack→Cartridge Slot Stack方向に固定することを明記

### 6. 検証結果

ModelSimで以下を確認した。

- `src/msx_slot/test_001`: PASS = 69, FAIL = 0
- `src/test_003`: PASS = 91, FAIL = 0
- いずれも Errors = 0, Warnings = 0

### 7. 現時点の注意点

実機のMENUキーによる`dump_slot0()`で、Slot0-0がすべて`FF`になる現象が残っている。

今回の整理では、`dump_slot0()`はPicoのDirectFlash readではなく、Picoが通常スロットアクセスでSlot0 ROMマップを読む正しいテストであると確認した。
したがって、次回は以下を優先して調べる。

- 通常スロットアクセスでSlot0-0 page0/page1を読んだとき、`slot_rom0_ce_n`がLowになるか
- `slot_a`がROM0物理アドレス `00000h` / `04000h` 系へ正しく変換されているか
- BootROM overlay (`bootrom_en`) や内部device応答がPico通常peekのSlot0 readを先に完了させていないか
- FlashROM0が `slot_rom0_ce_n`, `slot_rd_n`, `slot_a`, `slot_d` 経由で正しくデータを返しているか

### 8. 実機での最終確認

その後、最新の状態を実機へ書き込み、以下を確認した。

- MENUキーによる `dump_slot0()` が期待通り動作するようになった。
- Cartridge Slot Stack試作基板を取り付けた状態でも起動する。
- Cartridge Slot Stackに取り付けたROMカートリッジも動作する。

これにより、試作基板向けのI/Oカートリッジ暫定非対応方針、Slot1/Slot2メモリreadのみ外部カートリッジからCPUへ返す方向制御、
Slot0/Slot3の内蔵ROM/SSRAMマップ整理は、現時点の実機構成で有効であることを確認した。

ここで本件は一区切りとする。
