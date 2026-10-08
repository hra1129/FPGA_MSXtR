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

---

## 2026-09-22 作業履歴 (FlashROM Direct Access分離とMSX1 BIOS/ROMカートリッジ起動確認)

### 1. FlashROM書き込み失敗の症状

Picoから5キーで実行するFlashROM書き込みが不安定に失敗することが判明した。
ROM0 eraseは成功するが、ROM0 program中に毎回異なるアドレスでverify timeoutとなり、
該当byteが`0xFF`のまま残る症状だった。

例:

```text
Erase ROM0... OK
Write ROM0: /bios/msx2p.rom
FlashROM timeout at 0x00006: expected 0x98, actual 0xFF
```

その後、`flashrom_write()`でもSPI送信後に`SPI_INTR`を待つよう修正したところ、
書き込みは大きく進むようになったが、`0x0FFFF`付近で失敗するケースが残った。

```text
FlashROM timeout at 0x0FFFF: expected 0xFF, actual 0x00
```

このアドレスがMSX通常空間ではSecondary Slot Register (`FFFFh`) と重なるため、
FlashROM Direct Accessが通常MSX peripheralへ漏れている可能性が高いと判断した。

### 2. Direct Accessと通常MSXアクセスの整理

`ip_spi`の`0Dh`/`0Eh`はFlashROM Direct Accessであり、次の仕様で扱うべきと整理した。

- 20bit物理アドレスを直接FlashROMへ指定する
- `0x0FFFF`はFlashROMの物理`0x0FFFF`であり、Secondary Slot Registerではない
- `0x10000`など16bitを超えるアドレスも直接指定できる
- 通常MSX accessでは`A[19:16]`を無視し、slot/mapper/secondary等の通常デコードを使う
- Direct Access中は通常MSX peripheralへ副作用を出してはいけない
- ただし物理信号としては`slot_a`, `slot_rd_n`, `slot_wr_n`, `slot_rom*_ce_n`, `slot_d`を共有するため、`msx_slot.v`へは現状通り通す

### 3. `FPGA_MSXtR_CPU_Stack.v`のDirect Access分離

`msx_bus_mux`から出た`device_*`系信号は、FlashROM Direct Access中でも通常MSX peripheralへ
流れていた。これにより、`device_address == 16'hFFFF`のときに`secondary_slot`等が反応しうる構造だった。

そこで、トップレベルで次の分離を追加した。

- `w_device_flash_direct = w_cpu_sel[1] & w_pico_bus_flash_en`
- `w_device_valid_peripheral = w_device_valid & ~w_device_flash_direct`

通常MSX peripheral群には`w_device_valid_peripheral`を渡し、FlashROM Direct Access中は
以下の通常peripheralが動かないようにした。

- Secondary Slot Register
- Memory Mapper
- SSRAM
- BootROM
- PPI
- S2026
- RTC
- System Flag
- Pause LED

一方、`msx_slot.v`にはDirect Accessを通し続け、FlashROM物理信号生成は従来通り行う。

### 4. 検証

`src/test_003`で統合回帰を実行し、以下を確認した。

- Z80/R800切替
- Pico所有中のZ80/R800停止
- CPU復帰
- VDP write 1000回
- コンパイルエラー・警告なし

結果:

```text
PASS = 91, FAIL = 0
All tests PASSED.
```

### 5. 実機確認

MSX1 BIOSを書き込み、実機で以下を確認した。

- FlashROM書き込みが成功するようになった
- MSX-BASIC 1.0 が起動する
- Cartridge Slot Stackを取り付けた状態でも起動する
- ROMカートリッジを装着して起動する

これにより、FlashROM Direct Accessが通常MSX peripheralへ副作用を出す問題は解消し、
MSX1構成でのFlashROM書き込み、MSX-BASIC起動、ROMカートリッジ起動まで確認できた。

### 6. 残課題

これまで動作確認に使っていたROMカートリッジとは別のカートリッジで、動作しないものが見つかった。
また、MSX2+ BIOSでは起動ロゴまで到達せず暴走する。

ただし、これらは今回のFlashROM Direct Access分離修正とは別課題と判断する。

本日の作業はここで一区切りとする。

---

## 2026-09-23 作業履歴 (正常に起動しないROMカートリッジの調査)

### 1. 起動しないROMカートリッジと起動するROMカートリッジ

手元にあるいくつかのROMカートリッジの動作を確認したところ、大半が起動しないことが分かった。

(1) キャッスルエクセレント
　→ 起動するが、主人公は左へ移動し続ける。

(2) ボコスカウォーズ
　→ 起動する、普通に遊べる、特に異常なし

(3) ロードランナーII
　→ 起動早々にPCGがぐちゃぐちゃ。そのまま何かアニメーションしてるけどよくわからない。

(4) RabbitAdventure
　→ 画面に 1 が敷き詰められて暴走。上のやや右に 0 が居るのは先ほどと動作変わらず。
　　 表示は崩れているが、Spaceキーを押すとゲームが始まる。背景の表示は崩れたままで、
　　 スプライトキャラクターが表示されるが、主人公は左へ移動し続ける。

(5) ドラクエ2 MSX1版
　→ MSX System Version 1.0 の隣に「み」と表示してハング

(6) スーパーコブラ
　→ MSX System Version 1.0 の下にゴミが表示されてハング

(7) ギャラクシアン
　→ MSX System Version 1.0 の表示が終わったら、また MSX System Version 1.0 と表示され、その繰り返し

一部の MSX1ソフトは、SLOT#0 が拡張スロットになっていると動作しないものがあり、
ギャラクシアンは、そのタイプではないか？」という情報を得た。
今の環境は、SLOT#0 が拡張スロットであるため、ひとまずキャラクシアンの調査は保留とする。

### 2. 状況分析

これまで、スロット経由のアクセスは「正常に読み出せない」「正常に書き込めない」ということが起因で、不具合発生しているケースが多かった。
ROMカートリッジなので読み出せれば問題ない。
Pico の MENUキーを押したときの BIOSダンプテストに、SLOT#1 のダンプも追加して様子を見てみる。

### 3. Picoファームの修正と確認

dump_slot0() を dump_slot() に改名し、SLOT#1 のダンプも追加する。
ついでに、その後の起動に悪影響が無いように、スロットレジスタの内容は、元に戻すように修正した。

スーパーコブラのカートリッジを装着した状態で SLOT#1 の 4000h～40FFh をダンプしたところ、
期待通りに読み出せたので、「読み出し失敗による暴走」は考えにくい。

スーパーコブラのコードを解析してみると、SSGレジスタを読んで処理している部分が冒頭に多数あるのを確認。

### 4. 考察

スーパーコブラの冒頭処理では、SSGレジスタの読み出しが多数行われていることから、
SSGが存在していないことが、暴走の原因ではないか？

### 5. Dummy SSG 追加

SSG のレジスタを再現する Dummy SSG を追加した。
これにより、スーパーコブラの挙動が変わるかどうかを確認してみたところ、正常に起動するようになった。
しかし、その他のソフトに関しては、状況変わらず。

### 6. 左へ移動し続ける問題

キャッスルエクセレントと、RabbitAdventure で主人公が左へ移動し続ける問題が発生している。
この問題の切り分けのために、SSG のジョイパッド状態取得で、左キーを強制的に「解放」で返すようにして、
PPI のキーマトリクスも左キーに対応するビットを「解放」で返すようにした。
キーボードもジョイパッドも左を押していない状態で起動したが、両ソフトともに左へ移動する現象は改善せず。
→ Dummy SSG に対するリセット信号がちゃんとつながっていないというバグが原因だった。
　 修正したところ、キャッスルエクセレントと RabbitAdventure の両方で、主人公が左へ移動し続ける問題は解消した。

## 2026-09-24 作業履歴 (Y8960 Cartridge 音対応)

Y8960 Sound Cartridge の RTL をコピーしてきて、FPGA_MSXtR_SND_Cart_000 を追加した。
基板も Y8960 Sound Cartridge をそのまま使い、そこから音声を出力できるようにする。
SSG と OPLL を搭載し、カートリッジスロットから I/O write だけ出すことによって、write only の SSG + OPLL を
制御できるようにする。

FPGA_MSXtR_SND_Cart_000 は、現時点で MSX実機において、音が出るのを確認した。
I/O Write だけを受け付けるようになっていて、データバスも入力（CPU からみると write）のみ。

FPGA MSXtR に装着すると、音が出ない。I/O access をカートリッジスロットに出さないようにしたのが効いているようだ。
I/O write は、カートリッジスロットから出してもバス競合問題は起こらないので、I/O write だけスロットに出す修正を加える。

### 1. カートリッジスロットへ I/O write 出力追加

|スロット信号|状況|
|---|---|
|slot_iorq_n|CPU/SPIの iorq_n がそのままつながっているので修正の必要なし|
|slot_wr_n|CPU/SPIの wr_n がそのままつながっているので修正の必要なし|
|slot_data_dir|~w_external_memory_read が繋がっており、I/O write の場合は出力方向になるので修正の必要なし|
|slot_d|w_slot_wr_n ? 8'bz	: w_slot_d となっており、I/O write の場合はスロットに出力される|

Y8960 Sound Cartridge は、クロックは slot_clock_n を使っておらず、内蔵しているクロックで動作する。
そのため、上記信号の接続があれば音が鳴るはずであるが、鳴らない。

調べてみたところ、OUT系命令が、OUT (n),A しか正常に動作しておらず、OUT (C),A; OUTI; OTIR; OUTD; OTDR は、書き込むべきデータを
正常に出力できていなかった。
期待する出力になるように修正したところ、Rabbit Adventure の表示崩れが解消し、ロードランナーII の表示崩れも解消した。
一方で、スーパーコブラの音崩れは、若干変化はあったものの、まだおかしなままだ。
メガROM系は、試したカートリッジはすべて起動しなかった。（ハイドライドII, R-TYPE, ガルフォース, ドラクエ2 等)
バンクレジスタの書き込みが失敗しているのではないかと予想しているが、まだ本当の原因の確認はできていない。

---

## 2026-09-29 作業履歴 (MSX2+ 起動ロゴ非表示の原因特定)

### 1. デバッグ信号の整理

CPU FPGA の SPI コマンド 0Ah によるデバッグ出力から、短いサイクルで変化する CPU/共有バスの valid・ready・active、クロック、スロット選択・バス信号、INT/FFFFh 書き込みトラップを除いた。これらのデバッグ専用 RTL 信号・レジスタも削除した。
代わりに system_flag の F3h/F4h/F5h ラッチ値を出力し、Pico ファームのデバッグ表示から確認できるようにした。SPI 応答は従来どおりデータ 20 バイトと通信確認用 A5h の計 21 バイト。
Pico ファームは WSL から make -j でビルド成功。ModelSim では SPI 単体テスト 61 PASS、CPU 統合テスト 95 PASS、いずれも FAIL なし。

### 2. 実機での観測

更新した FPGA と Pico を実機に書き込み、カートリッジなしの MSX2+ BIOS で MSX-BASIC 3.0 の起動を確認した。ただし起動ロゴは表示されなかった。
BASIC 起動後のデバッグ表示では Z80 PC=0D6Fh、F3h=00h、F4h=80h、F5h=A3h、通信確認パターン=A5h だった。F4h=80h は SUB-ROM がタイトル処理の呼び出しから戻った後の値と整合するが、ロゴの描画成功を意味するものではない。
BASIC から `OUT&HF4,0:DEFUSR=0:A=USR(0)` を実行しても、ロゴも黒画面も出ず、すぐに BASIC 3.0 に戻った。起動時の黒画面はロゴプログラムによる黒塗りとは限らず、それ以前の表示状態が残っていた可能性がある。

### 3. 原因と解決

MSX2+ の EXT-ROM はタイトル表示処理から、ページ1の漢字ドライバー領域にあるロゴ本体を呼び出す。使用していた ROM イメージでは漢字ドライバー部分だけを turboR 版に差し替えており、MSX2+ が期待する位置に起動ロゴのプログラム本体が存在しなかった。turboR 版の起動ロゴは別の領域に配置されている。
漢字ドライバーを MSX2+ 版に差し替えて実機で再確認したところ、起動ロゴが正常に表示された。今回のロゴ非表示の原因は VDP アクセスや F4h のリセット判定ではなく、MSX2+ の EXT-ROM と turboR 版漢字ドライバーの組み合わせによる ROM 配置の不一致だった。

### 4. CR800 ラッパーへ CZ80 のタイミング修正を反映

`cz80_inst.v` に入ったバス制御タイミング修正を、対応する `cr800_inst.v` に反映した。

- /MERQ の M1 リリース位置とメモリサイクルのアサート/リリース位置を CZ80 側に合わせた。
- /MERQ と `slot_d_oe` の状態判定を `w_t_state` から、更新前の状態を保持する `ff_t_state_d` に変更した。
- メモリ /WR の立下り/立上りカウントを CZ80 側に合わせた。
- CR800 固有の I/O タイミング設定や、その他のバス要求処理は変更していない。

### 検証

- `cr800_inst.v` のエディタ診断でエラーなし。`test_002/run.bat` はコンパイル・シミュレーションまで完了した。
- 統合テストは PASS=4、FAIL=1。失敗は「Pico VDP write が1000回スロットへ到達」のチェックで、観測値は `pico_vdp_write_count=0`、`mcu_accept=2`、`bus_valid_cycles=2`。
- テストベンチではPicoへバス所有権を移す呼び出しがコメントアウトされているため、失敗はPico所有状態を前提とするテスト設定との不整合が疑われる。CPUラッパー修正との因果は未確認であり、回帰全体は未通過として扱う。

---

## 2026-09-30 作業履歴 (cr800 R800高速化改造と実機黒画面の調査・切り分け中)

### 1. r800.md に従った cr800_inst の全面改造

`src/cr800/r800.md` の仕様に従い、`cr800_inst.v` のタイミング制御を全面的に書き換えた。

- **コアの cen をフル速度化**: `cen = ff_run` (42.95454MHz 毎クロック)。旧 `ff_enable` (12クロックに1回) は廃止。
  メモリ/I/Oアクセス待ちは `ff_wait_n_i` でコアの T2 を引き延ばす方式に変更。
  アクセスの無いマシンサイクルは 1クロック/Tステートで最短終了する。
- **マシンサイクル分類FSM を新設** (CY_IDLE → [リフレッシュ] → CLASSIFY1/2 → INTERNAL | FLASH | ALIGN → SLOW):
  - SLOT#1/#2 メモリアクセスと I/O は `state_count` グリッドに同期し、cz80_inst と同じ位置の Z80 波形・速度で実行 (M1 は Z80 同様の1ウェイト付き)。
  - I/O は動的判定: 内部デバイスが `bus_ready`/`bus_rdata_en` を返したら波形を撤収して短縮終了。外部I/OはフルZ80タイミングで `slot_d` をラッチ。
  - オンボードFlashROM は /RD Low 6クロック (約140ns) の短縮波形。BootROM が先に応答した場合は `bus_rdata_en` 優先で早期終了。
  - 内部デバイスはハンドシェイク完了で即終了。非実装アドレスは 127クロックでタイムアウト (FFh)。
- **リフレッシュ**: 1msカウンター (`c_refresh_interval`=42954、パラメータでオーバーライド可) 満了後、次の M1 開始前に Z80 と同じ幅の `slot_rfsh_n` を出力。
  アドレスにはコアが M1 の T3/T4 に出す {I, R} を `!w_rfsh_n` 期間中にキャプチャして流用。
- **CPU切替**: 停止サンプルは M1 の T1 (`w_t_state==1 && !w_m1_n`)。停止中は毎クロック `run_req` を見て再開 (旧 `state_count==1` 条件はフル速度では成立しないため撤廃)。
- INT acknowledge では /RD を出さないようにした (旧cz80実装は M1 分岐で /RD が落ち、iorq+rd の偽I/Oリードになる恐れがあった)。
- `ff_bus_io` はサイクル終了 (CY_IDLE) で必ず 0 に戻す (msx_slot の kanji/data_dir デコードが bus_io レベルを参照するため)。

**分類信号の追加**: `msx_slot.v` に `cpu_slot12_cs` (プライマリスロット1/2、組み合わせ) と
`cpu_flash_cs` (rom0/rom1 デコード、1クロック遅延) の出力を追加し、トップで `cr800_inst` へ配線した。
CLASSIFY1/2 の2クロックは `ff_bus_address` 反映とデコード確定の待ち時間。cz80_inst は無変更。

### 2. ff_di 1クロック遅延機構の撤去 (重要バグ)

最初の実装では test_003 で R800 が暴走した。原因は旧設計の
`di = (t_state==1) ? ff_di : ff_bus_rdata` (ff_di は T1 で ff_bus_rdata を退避) が、
T1 = 1クロックのフル速度では「退避」と「コアの書き戻し (acc <= save_mux)」が同一エッジになり、
オペランド読みが直前オペコード値を返すハザードになること。
症状は `LD A,n` の A が 3Eh (自分のオペコード) になり、OUT のポート番号は正しいのにデータだけ化ける。
新設計では読み出しデータをサイクル開始時にクリアしないため、`di` を `ff_bus_rdata` 直結にして解決した。

### 3. cz80_inst.v の編集途中コード修正

`cz80_inst.v` に slot_d_oe 用 localparam の二重宣言 (c_wr_* を再宣言し、使用側は未定義の c_d_*) が
残っておりコンパイル不能だったため、宣言側を使用名 `c_d_*` に改名して解消した (値は c_wr_* と同一)。

### 4. シミュレーション結果

- `test_003` (Z80↔R800切替、OUT/IN/メモリタイミング、Z80のVDP write 1000回): **PASS=95, FAIL=0**
- `test_002`: PASS=4, FAIL=1 (既存のtb設定問題。昨日から変化なし)
- SDC に CPU コアのマルチサイクル制約はなく、フル速度 cen と矛盾しない。

### 5. 実機確認: タイミング収束OK、しかし黒画面 (未解決)

ビルドはタイミングバイオレーションなし。しかし実機起動で画面が黒一色のまま。
デバッグログでは Z80 は正常に動作 (PC進行、A8=FC、SSL3=08、F4=80、link=A5)。

**CZ80のスロット制御を差分照合した結果、I/O経路はコミット済みベースラインとピン等価で問題なし**:

- 今回の cz80_inst 差分は /MERQ (M1/メモリ) とメモリ /WR の位置変更のみで、I/O用 c_wr_io_*/c_iorq_*/c_rd_io_* は未変更。
- slot_d 駆動は「/WR Low」→「slot_d_oe」に変わったが、I/O の oe 窓は fall(d1,c1)/rise(d3,c5) で旧 /WR(io) と同一エッジ。
- msx_slot の SLTSL/CS merq ゲーティング (未コミットの別変更) はメモリ専用で I/O に影響なし。
- VDP Stack 側 msx_slot の取り込み条件 (iorq&wr 2段同期、Low中データラッチ) も満たす。

**本命の疑いは R800 フェーズ**: ログの mode_count=4 と R800_PC=04B9 から、起動中に
Z80→R800→Z80 が2往復している。turboR BIOS (msxtr.rom) は画面初期化を R800 モードで実行するため、
黒画面は今回改修した cr800_inst の実機挙動 (シミュレーションで検出できない箇所) が原因の可能性が高い。

実機でのみ顕在化しうる候補:

1. **FLASH短縮リード (/RD Low 6clk ≈ 140ns)**: R800 は BIOS ROM をこの窓でフェッチする。
   シミュレーションのフラッシュモデルは遅延ゼロのため、実機のアクセスタイム＋基板遅延が窓を超えるとコード化けする。
2. R800 の外部I/O書き込み (VDP): 波形は Z80 と同一設計だが、シミュレーションでは UART(10h) しか実証していない。

### 次回への申し送り (切り分け手順)

1. **msx2p.rom (R800を使わないBIOS) で起動確認**。昨日表示成功した構成。
   表示が出れば CZ80/Z80 経路の健全性が実機で確定し、R800 フェーズ起因と絞れる。
2. R800 起因と確定したら、まず Flash リードを Z80 速度に落として再確認:
   `cr800_inst.v` の CY_CLASSIFY2 で `flash_cs` の分岐も CY_ALIGN 行き (slot12 と同じ扱い) にする1行変更。
   これで直れば Flash アクセス余裕不足なので、短縮窓を 6clk → 10clk 程度に広げて再測定する。
3. それでも直らなければ R800 の外部 I/O 書き込みをロジアナで実測する
   (slot_iorq_n/slot_wr_n/slot_d と、CY_ALIGN→CY_SLOW の波形開始位置)。

### 関連ファイル

- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cr800/cr800_inst.v — フル速度cen化、マシンサイクル分類FSM、1msリフレッシュ、ff_di撤去
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cr800/r800.md — 今回の改造仕様
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/msx_slot/msx_slot.v — cpu_slot12_cs / cpu_flash_cs 出力追加
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/FPGA_MSXtR_CPU_Stack.v — 分類信号の配線追加
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cz80/cz80_inst.v — slot_d_oe用localparamの二重宣言を c_d_* に改名 (コンパイル修正のみ)

---

## 2026-09-30 夜 作業履歴 (R800キャッシュ高速化・実機目標達成・初回CHGCPU異常の調査)

### 実機の現状

朝の黒画面は電源を入れ直した後に解消し、その後はMSXturboR BIOSで繰り返し起動した。上の「黒画面はR800が原因」という推測は確定原因ではない。ユーザーが当時の構成をGitHubへcommit/push済み。

R800へ切り替えてBASICの `FOR I=0 TO 10000:NEXT` を測ると、当初78カウント (Z80は297、本物のR800は57)。R800専用のSSRAMキャッシュを実装した。

- 内部SSRAMの読み出しだけを対象とし、8KB、4-way set associative、8byteライン、pseudo-LRU、ライトスルー。Z80/Picoはキャッシュを通過する単発アクセスのまま。
- CPU切替時はvalidを無効化。データとタグは独立したシングルポートBSRAM階層 (`r800_cache_ram.v`) に格納。直接配列へbyteとラインの両方を書いていた初期版は65,536 DFFとして合成されIF0008で失敗したが、階層化後はキャッシュの4wayに計12個のシングルポートBSRAMが推論され、合成成功。
- 当初のライン補充は単発8回。SSRAM向けのR800専用8byte連続読み出しへ変更し、1回のCSで補充するようにした。215MHz側で8byteを保持し、完了トグルと64bitデータを42MHz側へ渡す。Z80/Picoの単発read/writeは維持。
- R800の内部デバイス待ち127クロックの打ち切りが8byte補充中に発火し得たため、SSRAMアクセスは完了までT2を保持するよう修正。160クロック待ちの回帰を追加した。

実機のデバッグ表示でR800動作中のキャッシュ統計は、hit=16,536,394→16,660,808 (+124,414)、miss=119→119、fill_wait=3451→3451クロックだった。ヒットは大量だがこの間はミス無し。BASICの78カウントはバースト後も変わらず、ミス待ちはこのベンチの主因ではないと判明した。

そのためFPGA SPI 0Ahの診断データを従来の20byteから32byteへ拡張し、既存フィールドを維持して上位12byteにR800キャッシュの累積hit/miss/補充待ち(各32bit、little endian)を追加。最後のA5hを含め33byteをPicoが受信し、3キーのログに表示する。

### R800専用MAIN-ROMキャッシュ

ROMフェッチ高速化のため、SLOT#0-0のMAIN-ROM (ROM0先頭32KB) だけに8KB・4-way・8byteラインの読み出し専用キャッシュを追加。R800のみ対象で、SUB-ROM/漢字ROM/他のROM0領域とBootROMは除外。ヒット時は外部/RDを出さず、ミス時は元の6クロック (約140ns) のread窓で8byteを補充する。MAIN-ROMチップは70ns品。CPU切替時にキャッシュを無効化する。Z80/PicoのROM経路は変更していない。

ROMキャッシュ後の実機BASICベンチは55カウントとなり、本物のR800の57を上回って目標性能に到達した。Gowinの合成・配置配線・書込みはユーザーがGUI側で実施する方針 (CLI合成ではGUIのプログラマーを起動できない)。

### シミュレーションとビルド

- ModelSim `src/cr800/test_001`: キャッシュの補充・ヒット・write-through・所有権切替時無効化、実Serial SRAMモデルの1-CS/8byteバーストと単発への復帰、160クロック待ち、ROMキャッシュ、70ns遅延ROMでの命令実行を検証。ROMミス時は8回外部read、同一ラインのヒット時は外部read無し。
- `src/spi/test_002`: 33byte診断レスポンスと末尾A5hを含め61 PASS / 0 FAIL。PicoファームはWSL `make -j4` でビルド成功。
- `src/test_003`: CPU切替など95 PASS / 0 FAIL。`src/test_002` は以前からPico VDP書込み件数の1項目が失敗 (4 PASS / 1 FAIL)。今回の修正で生じた新規失敗ではない。

### 未解決: BASICからの最初のCHGCPU(0180h)

BASIC起動後、C000hへ `3E 01 CD 80 01 C9` (`LD A,01h; CALL 0180h; RET`) をPOKEし、`DEFUSR=&HC000:A=USR(0)` を実行すると、初回だけSyntax ErrorまたはSCREEN 1→SCREEN 0への変化のどちらかがランダムに起こる。その後はR800へ切り替わって動作する。**この異常はROMキャッシュ追加より前、BASICから切替できるようになった時点から存在した**。キャッシュだけを原因扱いしないこと。

CHGCPUのA=01hはR800 ROMモード、A=02hはR800 DRAMモード。後者のROM内容をMapperRAMへコピーしてSLOT#0-0へ配置する機能はこのFPGAには未実装なので、02hの挙動をROMモード01hの正常な比較対象にしない。

ROM原本 `controller/bios_image_tool/bios/a1stbios.rom` (32KB) は結合版 `msxtr.rom` の先頭32KBと完全一致。SUB-ROM `a1stext.rom` は結合版の20000h、MSX-MUSIC `a1stmus.rom` は14000h。MAIN-ROMでは0180hが `JP 046Ah`、0484hの `ED 73 FD FF` は `LD (FFFDh),SP`、04BBhの `ED 7B FD FF` は `LD SP,(FFFDh)`。BIOSは共有メモリFFFDh/FFFEhにSPを保存してから、切替先CPUで復元する。RTLはZ80/R800のレジスタをコピーしないため、切替瞬間の両PC/SPが同値であること自体は合否条件にならない。

`src/test_004/tb.sv` のROM0を `msxtr.rom` にし、最初の50msで切替時のPC/SPをログ化。起動時は Z80→R800: Z80 PC=1297h, SP=FFFFh / R800 PC=0000h, SP=FFFFh、その後 R800→Z80: Z80 PC=1297h, SP=FFFFh / R800 PC=04B9h, SP=FFFFh。後者は04BBhのSP復元より前の位置。**これはBIOS起動時の切替であり、BASIC起動後の初回0180h呼出しはまだ再現していない**。BASIC起動までのフルシミュレーションは時間がかかりすぎる。

### 明日の調査候補

フルBASIC起動シミュレーションを延ばすより、初回CHGCPU前後だけを狙う。Z80がFFFDh/FFFEhへ保存したSPと、R800が04BBhで実際に読み復元したSPを比較する。同時に双方のPC/SP、S2026切替要求・run_ack・バス所有権・復帰先、必要ならFFFDh付近への読み書きを記録し、Syntax ErrorとSCREEN 0のどちらになるかを実機の短いトレースまたは専用の短縮テストで切り分ける。原因はまだ未確定であり、BIOSが正しく保存・復元できているかを最初に検証する。

---

## 2026-10-01 作業履歴 (メガROMカートリッジ対策: スロットのバスタイミングを実機Z80へ合わせる)

R800の最適化は、後で手戻りにならないよう一時中断した。先にメガROMカートリッジが動かない問題に取り組んだ。CHGCPU初回異常も未着手のまま。

### タイミングの基準

- 1カウント = 42.95MHzの1クロック ≈ 23.3ns。12カウントでZ80の1 T-state。
- CZ80の `w_t_state` は `state_count` が0→1になる境界で変化する。`ff_t_state_d==N` の区間は **sc=2,3,…,11,0,1 の順**なので、`(N,1)` はそのT-stateの最後にあたる (`(N,4)` は `(N,1)` より前)。localparamを動かすときは要注意。
- CR800の `ff_eng_t` は sc=0..11 の順 (1:T1, 2:T2, 3:TW, 4:T3, 5:T4)。
- 参照資料: ngs.no.coocan.jp TechHan Appendix A.7 の「メモリサイクル 基本スロット」「I/Oサイクル 基本スロット」のタイミングチャート。

### 1. メモリ書き込み: データを /WR より前に出し、/WR より後まで保持する

以前から「`slot_d` を `/WR` より少し早く出すべき」という話があった。修正前は `slot_d_oe` が `/WR` と完全に同時に切り替わっていた。

- CZ80 (`cz80_inst.v`): `c_d_mem_*` を変更し、データは (1,10)→(3,10) の区間で出す。`/WR` は (2,5)→(3,6) のまま。**データは /WR より7カウント (約163ns) 先に出し、4カウント (約93ns) 後で解放する**。
- CR800 (`cr800_inst.v`): CY_SLOW のSLOT#1/#2メモリ書き込みで、まとめて代入していた `ff_wr_n` と `ff_slot_d_oe` を分け、CZ80と同じ位置にした (データはeng_t1 sc10から、/WRはeng_t2 sc5〜eng_t4 sc6、データ解放はeng_t4 sc10)。
- **実機: メガROMソフトの一部が動くようになった。**

### 2. I/O書き込み: 同様にデータを /WR より前後に広げた

別のメガROMソフトで、青いタイトル画面の次のネームエントリーのウィンドウと文字が白ではなく黄色になり、一部のフォントも崩れた。さらに、ゲーム開始後に画面表示が崩れて止まる。VDP書き込みを疑い、I/O書き込みも修正した。

- CZ80: `/WR` と `/IORQ` は (1,1)→(3,5) のまま。データを `c_d_io_*` = (1,10)→(3,9) とし、**3カウント (約70ns) 先に出して4カウント (約93ns) 後で解放する**。I/Oサイクルは開始時点でしか書き込みと判定できないため、`/WR` は動かさずデータだけを前に出した。
- CR800の外部I/O書き込み: データはeng_t1 sc1から出し、`/WR` の立下りをsc4へ遅らせた。`/WR` の立上りはeng_t4 sc5、データ解放はeng_t4 sc9。**CR800では `/WR` が `/IORQ` より約70ns遅れて下がり、Z80と少し波形が違う**。
- CY_FLASH (オンボードFlash) の書き込みは変更していない。
- **実機: 症状は変わらなかった**。なお、このソフトはR800を使わずZ80モードだけで動く。

### 3. メモリリード: 切り分け実験の後、実機Z80と同じ位置へ変更

データ用メモリリード (M1以外) はウェイトが無く、M1より余裕が少ないため、読み出しデータ化けで表示が崩れていると推測した。

- 切り分け実験: `cz80_inst.v` に `c_mem_read_wait` を追加し、1のときはM1以外のメモリリードにもM1と同じ仕組みで1ウェイトを入れた (約280nsの余裕が増える)。**実機で症状は変わらなかった → リードタイミングは主因ではない**。現在は `c_mem_read_wait = 1'b0` で無効 (コードは残してある)。
- 本修正 (実機Z80に合わせる): CZ80は取り込みを (3,2)→(3,6) (`c_rd_mem_latch_*`、T3の中ほど) に、`/RD` の立上りを (3,2)→(3,7) (`/MERQ` と同時) に変更。CR800のSLOT#1/#2メモリリードも、取り込みをeng_t4 sc6、`/RD` 立上りをeng_t4 sc7にそろえた。`/MERQ` の立下りから取り込みまでは19→23カウント (約535ns)。
- 取り込みは必ず `/RD` の立上りより前にすること。msx_slot の `z80_rdata = w_slot_rd_n ? 8'hFF : slot_d` のため、`/RD` が上がると値が FFh になる。
- **実機: 症状は変わらなかった**。ただし、実機Z80と波形がそろったこと自体は良い変更と判断した。

### シミュレーション

- 新規 `src/cz80/test_002` (`run.bat`、`pause` なし): CZ80とCR800の両方で次を測定。
  - メモリ書き込みのデータ先行/保持: どちらも 163ns / 93ns
  - I/O書き込みのデータ先行/保持: どちらも 70ns / 93ns
  - CZ80データリード: `/MERQ` の立下りから約489ns後にデータが出る「遅いROM」モデルで、A5hを正しく取り込めることを確認。取り込み位置を旧 (3,2) に戻すと FFh になって失敗することも確認済み。
- `src/test_003` 95 PASS / 0 FAIL、`src/cr800/test_001` 6項目すべてPASS、`src/test_002` 4 PASS / 1 FAIL (以前からある既知の失敗)。
- `src/msx_slot/test_001` は 65 PASS / 8 FAIL (Test 6 の SLTSL/CS 関連)。**今日の変更前から同じ8件が失敗している**ことを、変更を退避して確認済み。未調査。

### 残っている症状と次の調査候補

表示用データ (フォントや色) が優先的に壊れる一方で、プログラム自体は起動している点がまだ腑に落ちない。

1. **データの向き (`slot_data_dir`) の切り替えタイミング**: 現在は `msx_slot.v` で `~w_external_memory_read` (= `/RD` が0かつSLOT#1/#2のメモリリードの間だけカートリッジ→CPU、それ以外はCPU→カートリッジ) を組合せ回路で出している。`/RD` が変わるとすぐ向きが変わるので、切り替わり前後で衝突やHi-Zの期間が生じていないか、トランシーバの向きとOEの時間関係を確認する。可能性は高いと考えている。
2. **VDP側 (FPGA_MSXtR_VDP_Stack_002 の `msx_slot.v`) のスロット信号の扱い**: 実機MSX + V9968カートリッジの環境ではVDPコアが同じでも問題が出ない。ただしスロット信号の扱いは少し違う。現在の実装は85.9MHzで `/WR` を2段FFで同期し、同期後の `/WR` が0の間は非同期の `p_slot_data` を毎クロック上書きしている。さらに `bus_wdata = ff_slot_data` を固定せずに渡しているため、VDPの `bus_ready` が遅れると `/WR` 立上り後の値を使い得る。`/WR` の立下りを同期で検出してから一定クロック後に1回だけ取り込み、トランザクション終了まで保持する方式を検討する。
3. **バンク切り替え書き込みの取りこぼし**: `SLTSL` や `/CS` の出るタイミングはきちんと調整した記憶が無く、実機と同じか怪しい。チャート (MREQ 145, SLTSL 155, CS 195/185 など) と比べて確認する。
4. `src/msx_slot/test_001` の既存失敗8件 (SLTSL/CS) も、3と関係するかもしれないので確認する。

### 関連ファイル

- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cz80/cz80_inst.v — `c_d_mem_*`、`c_d_io_*`、`c_rd_mem_cycle_rise=7`、`c_rd_mem_latch_*`、`c_mem_read_wait` (実験用、0で無効)
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cr800/cr800_inst.v — CY_SLOW のメモリ読み書きと外部I/O書き込みの波形、`w_slot_latch` の取り込み位置
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/cz80/test_002/ — 新規のバスタイミングテスト (tb.sv / run.bat)
- labo/FPGA_MSXtR_CPU_Stack_001_RENEW/src/msx_slot/msx_slot.v — `slot_data_dir`、`z80_rdata` (今回は未変更、次の調査対象)
- labo/FPGA_MSXtR_VDP_Stack_002/src/msx_slot/msx_slot.v — VDP側のスロットデータ取り込み (次の調査対象)

---

## 2026-10-02 作業履歴 (CZ80 M1 /MREQ タイミング確認)

### 実機確認

- カートリッジスタックなしでBASICまで起動: OK。
- カートリッジスタックを取り付けてMegaROMカートリッジを起動: OK。
- 問題のゲームは黄色文字、フォント崩れ、しばらく動かすとハング。今回のM1タイミング調整後も症状に変化なし。

### CZ80 M1タイミング

- `src/cz80/cz80_inst.v`: M1時の `/MERQ` 立上り条件をT2 `(2,1)` からT3 `(3,1)` へ変更し、`/RD` より先に解除されないようにした。
- `src/cz80/test_002/tb.sv`: M1中に `/MERQ` が `/RD` より先に立ち上がると失敗するチェックを追加。
- `src/cz80/test_002/run.bat`: 両テストベンチの全階層波形を追加し、それぞれ `tb.wlf` / `tb_cr800_slot_write.wlf` に保存。
- ModelSim: `test_002` のCZ80/R800両テストがPASS。コンパイルエラー・警告なし。

---

## 2026-10-02 夜 作業履歴 (スロットデータ方向の切り分け・SSRAM setup最適化)

### 実機観測と slot_data_dir の仮説

- Cartridge Slot Stackなしでは起動するが、空のSlot Stackを装着すると起動しない。slot_data_dirを0固定しても症状は変わらなかった。
- **固定0の実験だけでは方向切替が原因かは判定できない**。`slot_data_dir` はSlot Stack側SN74LVC8T245のDIR制御であり、FlashROM0はそのトランシーバよりCPU FPGA側にあるため、ROM0読み出し経路を直接切り替える信号ではない。
- test_004のROM0データモデルと空スロットFFhモデルを併用し、誤ってRead方向になったときROM出力との競合を観測する案を試した。強いFFhドライバを加えたtest_004はSRAMモデルの大量ログ中に手動停止し、全体PASS/FAILは未確認。test_004/tb.svの実験用ドライバは未コミットで保持。
- `slot_data_dir` は `w_bus_write` に加え物理 `/WR` と `slot_d_oe` も見て、書き込みデータ駆動終了までCPU→Cartridge方向を維持するよう変更した。msx_slot test_001では76 PASS / 0 FAIL。方向固定実験で起動しなかった事実との因果は未確定。

### SSRAMタイミング違反と対策

- GUI PnRでsetup違反47 endpoint、TNS=-14.131ns、最悪slack=-0.777nsを確認。最悪パスは `clk215m` の `u_ssram/ff_state_2_s0/Q` → `u_ssram/ff_state_4_s0/CE`。SSRAM RTLに未変更の過去PnRでは同系統の最悪パスが+0.108nsだったため、配置変化で限界経路が悪化したものと判断。
- SDC制約は変更禁止の方針を維持。`ssram.v` の `w_sclk_fall` を、divider count=2で事前登録するFFに変更し、count=3で消費するstate tickの位相は維持した。状態デコードをtickの高ファンアウト経路から外す狙い。
- 回帰: test_002はPASS=4 / FAIL=1。唯一の失敗は従来からのPico VDP write count項目 (pico_vdp_write_count=0) で、今回追加のSSRAMタイミング変更との因果は未確認。SSRAMアクセス自体は継続して観測。
- test_001はTBの階層参照 `u_dut.w_active_bus_owner` が解決できずelaboration時に停止し、今回のSSRAM変更に対する回帰結果は得られなかった。
- Gowin GUI出力を保護するためプロジェクト一式をTEMPへ複製し、同じCST/SDCでGowin 1.9.12.03 Tcl合成・PnRを実行。setup/hold違反0件、clk215m Actual Fmax=216.511MHz (制約214.753MHz)、最悪setup slackは+0.038ns。最悪経路はSSRAMからSPI制御へ移動。元の `impl` は上書きしていない。

### 明日の確認事項

- slot_data_dir固定0はROM0を直接切り替えないため、この実験を根拠に方向仮説を否定・確定しない。空Slot Stack装着時の外部バス負荷や信号競合は未解決。
- SSRAMの最適化後slackは正だが+0.038nsと小さい。実機投入前にGowin GUIで同じ制約のPnRを行い、結果を確認する。
- 実機症状は未再確認。SSRAM最適化、方向制御の実験は未コミット。生成されたPnR成果物を含め、他の未コミット変更も保持する。

---

## 2026-10-03 作業履歴 (Slot Stack D6故障の切り分け・test_005・方向制御修正)

### 起動不能の原因とPicoダンプ修正

- Pico所有中のダンプでA8hが00hのまま、空のSLOT#1/#2でもSLOT#0-2と同じデータが出ていた。Controller_001の `fpga_outport()` に `s_bus_owner != BUS_OWNER_CPU` の逆条件があり、Pico所有時にI/O書き込みを送信せず戻っていた。ユーザーが `BUS_OWNER_PICO` へ修正し、実機のA8h読み返しが00h/FFh/55h/AAhへ正しく切り替わることを確認。
- ROM0ダンプを原本と比較すると、12h→52h、BFh→FFh、00h→40hなど、D6がHighに張り付くパターン。初期命令のJP 126BhもJP 526Bhへ化けていた。SLOT#1/#2誤選択とは別の不具合。
- Slot Stack単体でDIR-D6の抵抗は約1.4MOhm、逆極性では未接続。D6/D4/D2の電源・GNDへの抵抗は同程度で、抵抗だけでは短絡を特定できなかった。
- DIR=1固定、さらに/OE=1固定でも元のSlot Stack装着時だけ起動せず、D6張り付きが再現。スタックピンの/OEは3.2V、通電時D6=3.1Vに対しD4/D2=0Vを確認。
- 予備基板に必要部品を取り付けて交換すると本体が起動。**元のSlot Stack基板のD6系統のハードウェア不良が起動不能原因**と切り分けた。U3内部故障か配線不良かの部品単位の特定とは区別する。
- /OEとDIRの固定実験を止め、通常制御へ戻すとメガROMも起動。FlashROM0とVDPはレベルシフタよりCPU側にあり、DIRで読み出し経路自体が切り替わるわけではない。前日の方向仮説と、今回確定した基板個体不良は分けて扱う。

### test_005の作成と拡張

- 実機基板保護のため、CPU Stackトップ階層で実Z80を動かし、スロット信号・方向・バス競合を観察する `src/test_005` を追加。本物のBIOSやTEST_BOOTROMは使わず、短い検査用FlashROMをTB内で生成する。
- 初期化はDI、page3=SLOT#3-0、SP=FF00h、A8h=E4h。RAM探索を省略し、SerialSRAMの初期化待ち後にSPIでCPU所有権へ移し、MSXリセットを解除する。
- 共通検査コードをFlashROMの1000h、SLOT#1の4000h、SLOT#2の8000h、SLOT#3-0のC100hで順に実行。SRAM用コードと検査データ257バイトはFlashROMの2000hに置き、Z80のLDIRでC100hへコピーしてから実行する。SRAMモデルへ直接ロードしない。
- 各区間でM1 read、通常memory read、memory write、I/O read、I/O write、非アクセス内部サイクル、refreshの7項目を観測。IN A,(A8h)、OUT (98h),A、ADD HL,BC、PUSH HL/POP DEを含む。機械語生成箇所には各領域の命令アドレスとニーモニックをコメントで併記。
- CPU側slot_dとCartridge側cartridge_dを分離し、DIRと/OEによる双方向バッファをモデル化。カートリッジROMのデータ確定80ns、出力解除20nsを仮定。弱いプルアップと能動ドライバを区別し、同じ値でも多重駆動は競合として即停止する。
- 安全性検査はクロックと信号変化イベントの両方で行う。読み取り点の有効データ、/RDと/WRの重複、書き込み中のアドレス・データ保持、I/O期間の方向なども検査。全階層波形はtest_005.wlf、ログはlog.txt。成功時だけ終了コード0、失敗・10msタイムアウトは1。
- 強制競合 `+inject_contention` はROM0読み出しで競合を検出して終了コード1になることを確認。ModelSimの正常$finishもonbreakへ入るため、test_passedを参照して成功/失敗の終了コードを分けた。

### slot_data_dirの修正と検証

- IN A,(A8h)中、約467us・PC=400Fhで内部bus_ioが先に0へ戻り、物理/IORQと/RDがLowのままDIRがRead方向へ戻る違反をtest_005で検出。外部memory read判定へ `slot_iorq_n` を追加し、物理I/Oサイクル終了までCPU→Cartridge方向を維持するよう修正。
- その後の波形で、/MREQや/IORQ終了後に残ったアドレスだけでDIRがRead方向へ向く区間を確認。単純に/MREQ Lowへ限定すると、ROM出力解除20nsと方向復帰が重なり競合検査がFAILしたため、その試験変更は一度戻した。
- 最終修正は `/MREQ Low` と外部read許可条件を組み合わせ、その判定を42MHzの `ff_external_memory_read` に記録。現在判定とFFのORにより、Read開始は即時、終了後だけ1clk (約23.3ns) 保持する。I/O・書き込み・CPUデータ駆動・内部スロット等の除外条件は維持。
- test_005: 4区間すべてで7項目を観測しPASS、終了コード0。実行は約2.30ms。各区間の件数/観測クロックはM1=15、data read=1、memory write=1、I/O read=29、I/O write=1、internal=84、refresh=315。
- /MREQ解除後20nsのRead方向保持と次クロックでHighへ戻る検査70回もすべてPASS。msx_slot/test_001は76 PASS / 0 FAIL (既存の未接続ポート警告3件)。

### 実機結果と休憩後の再開点

- ユーザーが最終の方向制御を実機へ書き込み確認。**文字が黄色・フォント崩れのゲームは改善せず**。他のメガROMソフトもそれぞれ決まった異常動作になる。非メガROMは数分のプレイでも表示崩れ・暴走が観測されていない。
- 「同じパターンで崩れる」は観測事実。ただし特定アドレスの読み書きが原因というのは推測で、アドレスと症状の対応はまだ特定していない。
- メガROMのバンク切替書き込み、アドレス上位の決定遅延、切替直後のM1/通常リード、連続アクセスの違いを次の調査候補とする。表示崩れの原因は未確定。今回のDIR修正を原因解決済みと扱わない。
- 現test_005は専用のリニアROMモデルであり、バンク切替や部品固有の遅延、アナログ特性は未検証。PUSH/POPは最終SPのみを検査し、POP DEのデータ内容までは判定していない。
- まずtest_005を使い、必要なバンク切替モデルとアクセス列を追加して安全性とデータの正しさを比較する。シミュレーションで競合が検出される構成は実機へ投入しない。タイミング制約は変更しない。
- 今回は作業記録のみを追記し、commit/pushは行っていない。休憩後は現ファイルと差分を確認して続行する。

---

## 2026-10-04 作業履歴 (R800切替時のSP異常調査と動作構成への復帰)

### 1. 実機イベントログから得た手掛かり

Z80からR800へ切り替わるBIOS処理を2回採取した。どちらもFPGA/Pico間のSPIリンクは正常 (`A5h`)、
両CPUのreset_nはHighで、CPUモードはZ80のまま起動処理が進んでいた。

- Z80側はBIOS PC=0488hでFFFDh/FFFEhへ `78h/F0h` を書き込んでおり、ログ上の保存SPはF078h。
- R800側はPC=04BFhでFFFDh/FFFEhから `54h/F4h` を読み、SP=F454hとして復元を開始した。
- その後R800はF454h付近から値を読み続け、1回目はRET先0000h、2回目は1277hへ移った。
- この観測から、CPU切替前後のスタック受け渡し、特にFFFDhを介したSP保存・復元が一致していない可能性が高いと判断した。

ただし、ログは論理アドレスしか示しておらず、書込み時と読出し時に異なる物理ページを参照したのか、
書込み／読出し自体に問題があるのかは未特定。根本原因の断定には至っていない。

### 2. 観測回路追加とタイミング違反

原因特定のため、0180h入口のPC/SP/AF/HL/CALL戻り先、内部memory/I/Oアクセス、CPU切替、復元地点、
RET後PCを記録し、Picoから読むイベントloggerを一時追加した。ところが合成後のPnRで
clk215mにsetup違反18 endpoint、TNS=-0.947ns、最悪slack=-0.113nsを検出した。
上位違反はloggerではなくSSRAM内部の経路だったが、観測目的の変更と同時に稼働中のSSRAM回路まで
変更することになった点はリスクが高いと判断した。

一時的にSSRAMのアドレスnibble選択をシフトレジスタへ、burst byte格納をシフト方式へ変更したところ、
test_005、`+cpu_switch_ram`、test_006はPASSし、PnR違反は0、最悪slackは+0.028nsとなった。
しかし、そのbitstreamを実機へ書き込むと起動しなくなった。SPIリンクとCPU reset_nは正常で、
Z80はBIOS付近を実行する一方、R800 PCは04B9hで待機していた。

### 3. 観測・SSRAM変更の撤回

観測対象の稼働回路をこれ以上変えないため、今回追加した変更を撤回した。

- `ssram.v`をアドレスシフト前の状態へ戻した。アドレス送信は`ff_address`の状態別nibble選択、
  burst格納は元の`ff_burst_serial[ff_burst_index*8 +: 8]`。
- R800イベントloggerのtop接続、CPU内部debug出力、SPI13h/14hのtrace拡張、Pico側APIとキー操作を削除。
- Gowinプロジェクトからlogger登録を外した。診断用ソースは次回参照用に残すが、未登録・未接続。
- SDC、デバイス設定GW5A-25A、既存のCPU切替制御やVDP loggerは変更していない。

### 4. 復元後の検証

- `src/test_005/run.bat`: PASS。CPU/SSRAM slot accessとバス安全性を確認。
- `src/test_006/run.bat`: PASS。BIOSで10回の交互CPU切替と同一CPU呼出しを実行し、全レジスタ復元を確認。
- Controller_001 Pico firmware: WSL `make -j` 成功。
- Gowin `run all`: 合成・PnR・bitstream生成完了。setup/hold違反0、最悪setup slack +0.029ns。
- ユーザーが復元版bitstreamを実機へ書き込み、Z80で起動することを確認。

この復元により起動可能な状態へ戻った。R800切替時のSyntax Error再現は今回の実機確認では未報告であり、
復元の主目的はZ80起動状態の回復。test_006は切替・レジスタ復元のシミュレーションで、
BASICの式評価や実機のSyntax Errorを再現するテストではない。

### 次回への申し送り

- 現時点の主要手掛かりは、Z80がFFFDh/FFFEhへ保存したSPと、R800が同番地から読んだSPが不一致だったこと。
- 観測を追加する場合は、まず稼働中のSSRAM・バス・CPU切替回路を変更しない方法を検討する。
- 追加情報が必要なら、対象を限定した既存の読み出し・Pico dump、外部計測、またはシミュレーション専用計測を優先し、
  観測用ロジック自体のタイミング影響を事前評価する。
- 今日の時点では原因は未確定。R800切替時のSyntax Errorを再確認した上で、SP受け渡しと実際の物理メモリ対応を
  安全に照合する解析方法を改めて検討する。

今日は起動可能な構成への復帰と検証までで一区切り。次回、観測対象を変えない解析方法から再開する。

---

## 2026-10-05 朝 作業履歴 (最小SP観測・実機Syntax Error再現・キャッシュ経路の切り分け)

### 1. 観測対象を変更しない最小SP観測

前日の教訓を踏まえ、イベントRAMや追加のSRAMアクセスを使わず、必要なSPの2値だけを保持する方式を実装した。

- Z80/R800コアの実体SPを`p_sp`、wrapperの`debug_sp`を経由してtopへ出力。
- Z80所有かつPC=0488hの期間に`ff_z80_saved_sp`、R800所有かつPC=04BFhの期間に
  `ff_r800_restored_sp`を毎クロック更新し、それ以外は保持する。
- PCは命令完了前にも進むため、最初の一致だけで記録せず、一致期間の最後まで取り込む。
- MSXリセットおよび9キーのSPI14hクリアで両ラッチを5A5Ahへ初期化する。
  クリアはCPU/Picoどちらの所有中でも実行可能。追加のメモリ要求は出さず、SPI_INTRで完了を通知する。
- 3キーのSPI0Ah診断表示へSPの2値を追加。予約32bitを使用し、byte16-17にZ80保存地点SP、
  byte18-19にR800復元地点SPをlittle-endianで配置する。応答長33byte、既存cache counter、
  70MHzのSPI速度および1usのbyte間隔は維持。
- 前日のイベントloggerは未接続のまま。SSRAM RTL、CPU実行制御、SDC、デバイス設定は変更していない。

### 2. 実装・タイミング検証

- `src/test_006/run.bat`: 実BIOSを使う10回のCPU切替と同CPU呼出し、全レジスタ復元はPASS。
  保存／復元地点のSPラッチはEFE8h/EFE8hで一致した (呼出し前SP=F000h、CALLで2byte、PUSHで22byte使用)。
- 同テストで33byte診断SPIのSP位置と末尾A5h、非破壊読出し、リセット／クリアの5A5Ah、
  クリア信号が1回だけ発生しMCUメモリ要求を出さないことを確認。
- SPI0Ahは既存仕様でSPI_INTRを出さない。テストに入れた通知待ちを除去してPASSした。
- VDP logger/SPI回帰およびController_001のWSL `make -j` はPASS。
- 同一設定のGowin合成・PnRとbitstream生成が完了。setup/hold違反0件、最悪setup slack +0.020ns。
  追加前の+0.029nsから9ps小さく、余裕は依然として小さい。制約や対象回路を変えて回避していない。
- 追加前のbitstreamとSTAレポートを一時フォルダ
  `C:/Users/hra/AppData/Local/Temp/FPGA_MSXtR_sp_baseline_20261005_062726`へ退避した。

### 3. 最小観測版での実機結果

ユーザーが実機で「9で初期化、3でクリア確認、DEFUSR=&H180:A=USR(0)、Syntax Error確認、3で表示」を実行。
起動を維持したまま、初回CPU切替時の不具合とSP不一致を再現した。

| 項目 | クリア直後 | 初回USR後 |
| --- | --- | --- |
| CPUモード | Z80 | R800 |
| mode_count | 4 | 5 |
| Z80@0488のSP | 5A5Ah | F078h |
| R800@04BFのSP | 5A5Ah | F054h |
| 非選択CPUのPC | R800=04B9h | Z80=04B7h |

両時点ともA8h=F0h、SSL0=00h、SSL3=00h、CPU reset_n=1、link_pattern=A5h。
この観測で確認できたのは保存地点と復元地点のコアSPの不一致であり、
今回のFFFDhへの書込みが物理SRAMへ完了したことまでは証明していない。

### 4. memory_mapperとシングル／バースト経路の確認

- `memory_mapper_cs`は`device_io`と下位アドレスFCh-FFhの一致で決まる。
  メモリアクセスの`device_io=0`なら、FFFDh/FFFEhの下位byteがFDh/FEhでもマッパーは選択されない。
- マッパーレジスタの書込みは`bus_cs && bus_valid && bus_write`が必要。
  仮にFFFDh/FFFEhがI/Oと誤認されればページ1/ページ2のレジスタを選び、ページ3を直接更新するわけではない。
- ただし、マッパー読み出し応答の誤選択という候補も検討した。コード確認だけで実機の応答元を確定はしていない。
- `ssram`のシングル／バースト選択入力は`bus_burst`。Z80/Picoはシングルアクセスでcacheをバイパスする。
- R800はcache hitならSRAMへ要求せず、missなら8byte境界からバースト読み出しを行う。
  `r800_cache`側が`ff_address[2:0]*8`でbyteを選び、CPU向けのread応答を出す。
  FFFDhのmissではFFF8h-FFFFhを取得し、FFFDhは6番目、FFFEhは7番目のbyteを使う。

Z80が安定動作し、切替後にcache/burst経路が加わることから、R800側の復元読出しを優先候補とした。
ただし、Z80の今回の保存書込み成功は未確認のまま保留する。

### 5. BASICのPEEKによる追加情報

ユーザーがBASICで上から順に実行し、次の結果を得た。

```text
DEFUSR=&H180:A=USR(0)       -> Syntax error
? HEX$(PEEK(&HFFFD))       -> 54
? INP(&HFD)                -> 2
A=USR(0)                  -> 正常終了
? HEX$(PEEK(&HFFFD))       -> 78
```

初回の不一致はSPレジスタへの取り込みだけが壊れている説明ではなく、
FFFDhの読み出し値自体が54hとなっている可能性を強める情報。
INP(FDh)の値2は、その時点の54hがマッパーFDhレジスタの値そのものではないことを示す。
ただし、初回切替後のPEEKもR800/cache経路を通るため、物理SRAMに54hが残ったか、
SRAMには78hがあるのにcacheが古い54hを返したかは未確定。

### 帰宅後の再開点

- 第一に分けたいのは「Z80の保存書込みが反映されず古い54hが残った」と
  「保存書込みは成功したがR800/cache経路が古い54hを返した」の二択。
- R800がFFFDh/FFFEhの応答として受け取った2byteを小さく保持すれば、read経路とSPへの取り込みを分けられる。
  ただし、実装はまだ行っておらず、観測対象への負荷を評価してから判断する。
- Picoによるcacheを通らないreadも候補。ただしR800からPicoへの所有権切替自体がcacheを無効化するため、
  比較時点と副作用を明確にした手順が必要。Z80へBIOS切替して読むとFFFDh自体を書き換える可能性にも注意する。
- 追加する観測は必要最小限に限定し、SSRAM・cache・CPU切替の稼働回路やSDCを変えずに解析する。

出勤のため、ここで作業を中断。根本原因は未確定で、回路修正や追加観測は帰宅後に再検討する。

### 6. 帰宅後: R800 cache line無効化・再取得の専用シミュレーション

実機でBASICのPEEK(FFFDh)が54h、Pico所有中の直接PEEKが78hとなる結果を受け、
初期R800起動→Z80復帰後に作られた古いstack cache lineが、Z80の次の更新後も有効のまま残る可能性を検証した。

`src/test_006`に`+cache_sp_reuse`ケースを追加。起動準備中のR800→Z80経路は既存のままにし、
その後Z80→R800→Z80→R800を実BIOS・実CPU・SSRAMモデルで実行する。

- 1回目: caller SP=F06ChからCALLし、BIOSがFFFDh/FFFEhへF054hを保存。R800がF054hを復元。
- R800からZ80へ復帰後、2回目はcaller SP=F090hからCALLし、FFFDh/FFFEhをF078h/F0hへ更新。
- 2回目のR800がSP=F078hを復元し、callerへSP=F090hで戻る。
- cache missによる物理SSRAMライン03FF8hのburst readを数え、1回目・2回目それぞれ発生することを確認。
- TBから物理SSRAMモデルのFFFDh/FFFEhも直接確認し、書込み値が54h/F0hから78h/F0hへ変わることを照合。

結果: PASS。起動準備後のZ80→R800→Z80→R800、FFFDhの物理書込み、stack line 03FF8hの2回のburst refill、
R800 SPのF054h→F078h復元を確認。現在のRTLではR800が非activeへ移ると全cache validを消し、
次のR800 missでSSRAMから更新値を再取得できることがシミュレーション上で確認された。

この結果は、実機で観測したR800の54hについて原因を特定しない。実機ではcache invalidationが失敗しているのか、
burst refillの戻り値が化けるのか、slot/page/電気的条件が異なるのかは未確定。
特にテストはSerialSRAMの論理モデルであり、実チップのタイミングや信号品質は再現しない。
RTL、SSRAM、SDCへの変更は行っていない。

## 2026-10-05 夜 作業履歴 (R800 cache valid 64clock clear FSM)

`ff_valid`全配列を1clockでclearするRTLが、実BSRAMでは全entryへの書込みにならない懸念に対し、
64行×16bitのvalid RAMと明示clear FSMを実装した。reset解除後およびR800 inactiveへの遷移後に、
1行ずつ64clockで0を書き込む。`cache_ready`をtopへ接続し、clear完了まではR800 coreの`run_req`を抑止する。

- valid RAMのlookup、fill、clearは同一alwaysブロックの排他的操作とし、Gowin合成後も単一BSRAMのwrite portを共有する形にした。
- 生成netlistでvalid用BSRAMのclear時write enable、clear rowのアドレス選択、DI=0となるdata muxを確認。
  `u_r800_cache`はBSRAM 13個 (cache data 12個 + valid 1個)、Register=945、LUT=1374。
- `test_006/run.bat`: PASS。TBはclear開始から完了までを計数し、各sweepが64 rising edgeであることをassert。
- `test_006 +cache_sp_reuse`: PASS。R800はclear中にrun_reqを出さず、stack line 03FF8hを2回refillし、SP F054h→F078hを復元。
- `test_005/run.bat`および`+cpu_switch_ram`: PASS。後者はcache hits=35、misses=8、fill_wait=232。
- 最新ソースでGowin合成、PnR、bitstream生成が完了。setup/hold違反0件、最悪setup slack +0.047ns。
  最悪パスは引き続きSSRAM burst serialのenable経路。SDC、SSRAM RTL、device設定は変更していない。

この結果でRTL sim上の64clock clearと合成BSRAMへのclear書込みは確認できたが、実機のFFFDh読出し問題が解消したとはまだ判断しない。
物理SerialSRAMの波形・信号品質はシミュレーション対象外のため、実機で最終確認を行った。

### 実機確認

最新bitstreamを書き込んだ実機で`DEFUSR=&H180:A=USR(0)`を実行。
Syntax Errorは発生せず、CPUが正常に切り替わってUSR呼出しが完了した。今回の64clock valid clear導入後、
当初の実機症状が解消したことを確認した。SP診断値やFFFDhのPEEK値については今回未報告のため、ここでは結論しない。

## 2026-10-06 朝 作業履歴 (MSX-DOS2 bank switch / FDC decode)

SLOT#3-2 page1 のMSX-DOS2 bank切替に向け、`dos_mapper`を追加し、既存の`msx_slot.v`内にあった`ff_dos_bank`を移設した。
7FF0h writeで`wdata[1:0]`を保持し、reset値はBANK#0。`msx_slot`はそのbank値でROM0のBANK#0〜3を選択する。

- `address_decode.v`にSLOT#3-2の7FF0h writeおよび7FF1h〜7FFBhのchip selectを追加。
- `dos_mapper.v`で7FF1h status read、7FF2h〜7FFBhの`/RDFDC`・`/WRFDC`とFDC addressをdecode。
  FDC/status未実装部のreadはFFh、busは即時完了。7FF0h readと7FFCh〜7FFFhはDOS ROM側に残す。
- 専用test_001は15 checks PASS。reset bank、4 bank値、7FF0h read-only動作、status/FDC範囲、予約領域、slot/I/O誤選択を確認。
- `msx_slot/test_001`: 99 checks PASS。`test_005`、`test_006`もPASS。
- Gowin合成/PnR・bitstream生成完了。setup/hold違反0件、最悪setup slack +0.027ns。

### 実機確認と次回調査

DOS2 ROM領域をFFhで埋めた状態ではBASICまで起動した。一方、実DOS2 ROMを書き込むと、起動時のDOS2初期化から戻らず停止した。
FDCを実装していないためstatus/FDC応答が原因と考えられるが、BASICまで起動するかはこの時点では未確認。

### 帰宅後の7FF4h polling調査

実機debugでZ80 PCが7971h〜7978h付近を反復し、7FF4hへのアクセスを観測した。
`a1stdosb.rom`のROM offset 3972hには`3A F4 7F E6 10 20 F9`があり、
`LD A,(7FF4h); AND 10h; JR NZ,-7`としてbit4が0になるまで7FF4hをpollする。
従来のFDC stubはread値が常にFFhだったため、bit4が常に1となってこのloopから抜けられない状態だった。

7FF4h readのみ00hを返す暫定idle responseを追加し、それ以外の未実装FDC readはFFhのままにした。
専用dos_mapper testは16 checks PASS (compile/sim warnings 0)。test_005、test_006もPASS。
Gowin合成/PnR・bitstream生成完了、setup/hold違反0件、最悪setup slack +0.015ns。
この暫定responseで実機がBASICまで進むか、またDOS2初期化が次にどのFDC状態を要求するかは実機再確認待ち。

### 7FF4h DRQ pollの追加確認

暫定00h responseを書き込んだ後のdebugでは、PCが7974h付近から7967h付近へ進んだ。
ROM offset 3960h付近には`LD A,(7FF4h); AND C0h; CP 80h; JR NZ,-9`があり、
7FF4hのbit[7:6]が`10b`になるまで再度pollしていた。00hはこの条件を満たさない。

7FF4hの暫定値を80hへ変更した。これは先行する`AND 10h == 0`条件と、後続の`(value & C0h) == 80h`条件を両方満たす。
専用testでaddress_decodeのCPU read mux経由でも80hになることを確認。dos_mapper 16 checks、test_005、test_006はPASS。
Gowin PnR/bitstream再生成完了、setup/hold違反0件、最悪setup slack +0.015ns。
実機でBASIC到達するか、以降に追加のFDC状態待ちがあるかは未確認であり、80hはFDC未実装時の暫定idle/DRQ応答である。

その後のdebugではPCが797Fh、7997h、7954h、7968h、79ADh付近を移動しており、80h固定では`(IX+13h)&20h`のresult待ちから抜けられない可能性が分かった。
ROMは7FF4h statusがC0hのとき7FF5h resultをreadし、そのbit5をIX+13hへ保存してから、status 80hへ戻る流れを持つ。

FDC未実装時の暫定one-shot handshakeとして、7FF5h write後の7FF4h readにC0h、続く7FF5h readに20hを返し、result read後に7FF4hを80hへ戻すstateを追加した。
dos_mapper専用19 checks、test_005、test_006はPASS。最新Gowin PnR/bitstream生成完了、setup/hold違反0件、最悪setup slack +0.014ns。
この合成resultで実機のDOS2初期化が完了する保証はなく、最新bitstreamでのBASIC到達確認と、次に止まる場合のFDC transaction観測が必要。

### TC8566AF最小command/result FSM

固定C0h/20hを返すone-shot stubを廃止し、再利用用`src/fdc8566/fdc8566.v`にDOS2 INIT向けの最小command/result FSMを実装した。
FRES release、SPECIFY/NDMA、READ DATA(46h)の9-byte command packet、未挿入diskの7-byte abnormal result、
SEEK/RECALIBRATEとSENSE INTERRUPT(08h)、unsupported commandのinvalid-command resultを扱う。
FDC実media transfer、DMA、disk image/Pico連携は対象外。FDC MSRはRQM/DIO/NDM/CB、IRQはINTE bitでgateする。

- `dos_mapper/test_001`: 42 checks PASS、warnings 0。ROM setup (F2=04h/F3=20h)、SPECIFY、READ DATA packet長/result、seek interruptとsense acknowledgeを検証。
- `test_005`、`test_006`: PASS、warnings 0。
- Gowin合成/PnR/bitstream生成完了。setup/hold違反0件、最悪setup slack +0.036ns。
  `u_fdc8566` Register=120、LUT=201。

このFSMはBASIC起動に必要な初期化応答に限定した暫定emulationであり、実ディスクのread/writeや一般的なFDC commandは未実装。

### 実機確認: Disk BASIC起動

FSM版bitstreamを実機で動作させ、MSX BASIC version 4.0、Disk BASIC version 2.01の表示後に`Ok` promptまで到達した。
DOSが有効な状態でBASIC起動する当初の目的を達成した。画面表示はDisk BASICが組み込まれて起動したことを確認するが、
実ディスクのread/writeや他のFDC commandが動作することまでは確認していない。現行`fdc8566`はDOS2初期化用の最小応答FSMとして扱い、
実ディスクアクセスを追加する際はcommand/phaseを段階的に拡張する。

## 2026-10-06 R800性能計測

BASICの入力待ちやPico/CPU所有権切替時間を測定窓に含めないよう、内部I/O F6h writeで計測開始、F7h writeで停止する方式を追加した。
両markerは即時readyでCPUを待たせず、R800選択中の受理transactionだけがR800計測FSMを制御する。

- `cr800_inst`が42.95454MHz基準でactive cycles、`/WAIT`期間、CY_FLASH期間、ROM cache hit/miss/fill cyclesを32bit計数。
- SPI command 0Fhでactive状態と6 counterをsnapshot read。既存SPI command 0Ahとその33byte形式は変更せず、0Fhは28byte little-endian payload + A5h marker。
- Pico `fpga_get_r800_performance()`とdebugger表示を追加。既存CPU debug表示の後にperf snapshotを表示する。
- marker decoder testは45 checks PASS。test005でSPI 0Fh応答の28byte長とA5h終端を確認。test006もPASS。Pico `make -j` PASS。
- 最新Gowin合成/PnR・bitstream生成完了。setup/hold違反0件、最悪setup slack +0.103ns。

BASIC測定例: benchmark前に`OUT &HF6,0`、測定終了直後に`OUT &HF7,0`を実行する。これで入力待ちは窓外になる。
0Fh snapshotはF7h後にdebuggerから取得する。カウンタの実機値と表示はまだ未確認で、BASIC `TIME`結果との相関も今後測定する。
ROM cache counterは現行R800 ROM cache実装対象（MAIN-ROM）だけを数え、Flash/DOS ROM全体のcache性能を示すものではない。

## 2026-10-07 R800 ROM0キャッシュ改修と実機性能確認

ROM cacheの対象をMAIN-ROM限定からFlashROM0全域（512KB）へ拡張した。
cache keyをCPU address下位15bitからROM0の19bit物理addressへ変更し、bankが異なる同一offsetを別lineとして識別する。
容量は従来の8KB（4-way、256 sets、8 bytes/line）のまま。512KB全体を常駐させる変更ではない。

- `msx_slot`に内部ROM0選択信号`cpu_rom0_cs`を追加。外部CEの`/MREQ` gateより前の選択をR800へ渡し、外部read開始前のcache分類を可能にした。
- topから`rom0_cs`と`rom0_address=slot_a`を接続。BootROMは除外し、ROM1はcacheをbypassして既存のFlashアクセス経路を使用する。
- ROM cacheはR800専用。`!run_req || !ff_run`で無効化し、R800からバス所有権を移す際に古いlineを残さない。
- R800のROM0 writeは外部Flashへwriteを出さず即時完了する。内部bus transactionは維持し、DOS2の7FF0h bank latch writeを外部ROM writeと分離する。
- 前節の「MAIN-ROMだけを計数する」という記述は改修前の状態。改修後のROM perf counterはROM0全域のcacheアクセスを対象とする。

### RTL検証と合成

- `cr800/test_001`: 全6 test tops PASS。19bit bank tagの非alias、line fill/hit、無効化、miss時の70ns ROM read、hit時の外部read省略を確認。
  既存RAM cache単体TBの`cache_ready`未接続warningは残るが、ROM cache/fetch testはwarnings 0。
- `msx_slot/test_001`: 99 checks PASS。`/MREQ`前のROM0内部選択、FDC overlayと非ROM mappingの除外を確認。
- `test_005`、`test_006`: PASS。slot access/bus safety、SPI性能snapshot形式、CPU切替とレジスタ復元を確認。
- Gowin合成・PnR・bitstream生成完了。ただし最初の改修後PnRではsetup violationが発生した。
  その後ユーザーが合成条件を変更して再合成し、タイミングバイオレーションが解消したと報告。変更後のslack数値は今回未報告。

### 実機確認: ROM0キャッシュとBASIC benchmark

DOS2組み込み（FDC stub）の初期化ルーチンがR800へ切り替えるため、BASIC到達時点でR800が動作している。
この状態で以下のbenchmarkを入力・実行し、画面の`TIME`値が改修前の8から5へ短縮したことを確認した。

```basic
10 DEFINT A-Z
20 OUT &HF6,0
30 TIME=0
40 FOR I=0 TO 1000:NEXT
50 OUT &HF7,0
60 PRINT TIME
```

本物のR800でも同benchmarkは5との報告があり、この測定では近い速度に到達した。
ただし`TIME`の分解能と単一benchmarkの結果だけでは、実機R800と本設計のどちらが速いか、また全命令の速度互換性は判断できない。

実行後のdebug log:

```text
FPGA CPU debug: Z80_PC=0x04B7 R800_PC=0x0D7E mode=R800
  CPU switch: mode_count=9
  SP capture: Z80@0488=0xEA98 R800@04BF=0xEA98
  Z80 bus: addr=0x04B7 reset_n=1
  R800 bus: addr=0xF3DE reset_n=1
  Shared bus: pause=0
  Slot map: A8=0xF0 SSL0=0x30 SSL3=0x08
  System flag: F3=0x00 F4=0x80 F5=0xEB
  R800 cache: hit=275767676 miss=1310 fill_wait=37990 cycles
  R800 perf: STOP total=4090376 wait=2513715 flash=0 rom_hit=289097 rom_miss=96 rom_fill=5376 cycles
  link_pattern=0xA5 (OK)
```

F6h/F7hで区切った測定窓でROM hit=289097、miss=96を観測し、従来0だったROM cache counterが実機で動作することを確認した。
ROM hit率は約99.967%。`rom_fill=5376`は96 misses × 8 bytes × 7 clocksと一致する。
`flash=0`は直接Flash経路の計数であり、ROM cache miss時の外部readが無かったという意味ではない。
先行する`R800 cache`行はRAM cache側の統計で、ROM perfの測定窓内counterとは区別する。

今回の区切りでは、ROM0キャッシュ改修後のBASIC benchmark高速化と性能counterの実機観測まで確認した。
他のROM bankを使うソフト、ROM1 cartridge、長時間動作などの広範な実機互換性確認は今後の対象とする。

## 2026-10-07 R800乗算命令 MULUB / MULUW

R800拡張命令のうち、仕様上動作が保証された整数乗算命令を`cr800`へ追加した。
命令実行時間はR800実機の14/36 clocksへ合わせず、正しい結果を保ちながら短く完了する実装とした。

- `MULUB A,r` (`ED C1/C9/D1/D9`): r=B/C/D/Eをサポートし、HLへ16bit積を書き込む。
- `MULUW HL,ss` (`ED C3/D3/E3/F3`): ss=BC/DE/HL/SPをサポートし、DE:HLへ32bit積を書き込む。
- 未定義operand encodingの動作は対象外。
- combinational 8x8/16x16 multiplyと結果writebackを使用。MULUBは1回、MULUWはHL/DEへ各1回のregister writeで完了する。
- flagsは仕様どおり、S=0、Z=product zero、P/V=0、C=上位積が0でなければ1とし、H/Nとundocumented X/Yは保持。
- `cr800_registers`に乗算operand用pair read portを追加。R800 state machineは乗算結果commit中のみ停止し、乗算結果の書戻しを優先する。

### 追加差分の検証

- `cr800/test_001/run.bat`: 全test tops PASS。
- `tb_r800_mulub`: B/C/D/E各operand、overflow carry、zero flag/resultを確認。
- `tb_r800_muluw`: BC/DE/HL/SP各operand、32bit DE:HL result、overflow/zero flagsを確認。
- `test_005`、`test_006`: PASS。slot/bus safety、CPU切替、register restoreへの回帰なし。
- Gowin合成・PnR・bitstream生成完了。setup 25 paths / hold 25 pathsはいずれも違反0。
  最悪setup slack +0.018ns、最悪hold slack +0.180ns。最悪setup pathは従来どおりSSRAM state経路。
- Resource: Logic 50% (LUT/ALU)、FF 23%、BSRAM 50%、DSP 6% (MULT12X12 x1、MULTALU27X18 x1)。
- 実機での乗算命令実行は未確認。対象はMULUB/MULUWであり、R800固有opcode全体やZ80未定義opcode群の完全対応を意味しない。

## 2026-10-07 R800/Z80挙動差分の追加

R800チェック資料で確認された差分のうち、SLL、連続DD/FD prefix、未使用F flagsを`cr800`へ反映した。

- `SLL r`のbit 0を0にし、SLA相当の結果とする。
- 既にDD/FD index stateがある状態で次のDD/FD prefixを受けた場合、index stateを解除する。
  これにより`DD DD 23`等はindex registerのINCではなく、通常opcodeとして`INC HL`になる。
- ALU、CPL/CCF/SCF、BITによるF更新ではF3/F5を変更せず保持する。`POP AF`による全F byte loadと
  `EX AF,AF'`によるAF bank交換は明示的なregister transferとして維持する。
- `cz80`のSLL、prefix、flags処理は変更していない。

### 検証結果

- `tb_r800_compat_differences`: PASS。`SLL A` (81h→02h)、`DD DD 23` (HLだけを1増加)、
  `POP AF`でセットしたF3/F5が`XOR A`とSLL後も保持されることを確認。
- `cr800/test_001/run.bat`: 全test tops PASS。`test_005`、`test_006`もPASS。
- Gowin合成・PnR・bitstream生成完了。setup/hold violation 0、setup最悪+0.018ns、
  hold最悪+0.180ns。最悪setup pathはSSRAM state経路。
- 実機での今回3差分の専用動作確認は未実施。

## 2026-10-08 漢字ROMを専用SerialROMへ分離

CPUの漢字ROM読み出しを外部ROM1から切り離し、専用SerialROMへ移行した。PicoによるROM1のDirect Flash accessは従来の選択経路を維持する。

- `src/kanji_rom/ip_kanji_rom.v`を追加。既存`ip_spi_rom`を基に、HOLD/WPなし・CS 1本のSPI FAST_READ (0Bh) 制御、JIS1/JIS2アドレス、各enable (`kanji1_en`/`kanji2_en`)、読出しデータ/readyを実装。
- CPU I/O D8h-D9hをJIS1、DAh-DBhをJIS2としてdecodeし、D8h-DBh以外を選択しない。JISアドレス変換とread後incrementは従来動作を維持。
- `msx_slot`からCPU Kanji readのROM1 CE出力を除去。Pico Flash accessのROM0/ROM1選択は維持。
- Gowin projectと全system test compile scriptへ新モジュールを登録。test001-test004にトップ階層で使う`vdp_logger.v`も登録。
- Kanji専用テストでJIS1/JIS2 SPI address、byte read、JIS1 increment、disabled JIS2のread bypassを確認しPASS (errors/warnings 0)。`dos_mapper` decodeテストは51 checks PASS。`msx_slot`は94 checks PASS (既存TB port warning 3件)。
- system test003は95 PASS / 0 FAIL、test004はerrors/warnings 0で完了。test005/test006もPASS。
- test001はTBが現行topに存在しない内部信号5個を階層参照し、elaborationで停止。test002はPico VDP write count=0の既知の1項目失敗 (PASS=4/FAIL=1) が継続。どちらもKanji個別・結合テストの失敗ではなく、今回未解決の回帰制約として扱う。
- Gowin合成・PnR・bitstream生成完了。setup最悪slack +0.072ns、hold最悪slack +0.189ns。Logic 51%、register 23%、BSRAM 50%。使用したデバイス/SDCは現行プロジェクト設定。

### 実機確認と次作業

SerialROM分離版bitstreamを実機へ書き込み、**MSXの起動に影響しないことを確認した**。ただし、D8h-DBhからのJIS1/JIS2漢字読出し自体と、PicoからのSerialROM書き込みはまだ未確認・未実装。

帰宅後は次の作業を行う。今回は出勤時間のため、ここで作業を中断する。

- PicoからSerialROMへ書き込むためのI/Fを追加する。
- ROM1をSLOT#1に装着し、メガROMとして使用できるモードを追加する。

## 2026-10-08 夜 Picoから漢字SerialROMを更新・照合するI/F

帰宅後、専用SerialROMの先頭256KBをPicoから更新する機能を実装した。ROM1のSLOT#1メガROM化は次の作業として残す。

- SPI 15hに任意アドレス1-256byte read、16hに256byte page program、17hに先頭256KB消去開始、18hにBUSY/error status取得を追加。
- 00000h-3FFFFhの範囲とページ境界をFPGA/Pico双方で検査する。全消去は64KB Block Eraseを4回行い、未使用の残り領域は保護する。
- 256byte全受信後にのみprogramを開始し、途中通信では書き込まない。Write Enable後のWELとprogram/erase後のBUSYを確認し、タイムアウトを通知する。
- `ip_kanji_rom`内のSPI制御をCPU/Picoで共有し、Pico所有中だけ直接操作を受理する。MSXバスには直接操作を流さない。SerialROM制御はFPGA reset、JISアドレスはMSX resetへ分離し、MSX reset中でも更新できる。
- R800内部デバイス待ち127clockに収まるよう、SPIの同一command内byte間待ちを短縮。TBでCPU向け漢字readが120clock以内に返ることを確認した。コマンド間CS-high時間は維持。
- Controller_001は `/bios/kanji.rom` の正確な256KBイメージを消去・1024ページ書き込み後、全256KBを読み戻して比較する。Pico所有中7キーで漢字のみ更新、4キーでROM0 BIOSと漢字更新、5キーでSerialROM先頭もダンプ。ROM1への漢字書込みを廃止。
- 更新失敗・照合不一致ではPico所有を維持しCPU復帰を抑止する。FPGA側もBUSY/error中のCPU復帰を抑止。更新は電源断に対して原子的ではなく、途中電源断後はmaintenance modeから再更新が必要。

### 検証

- Kanji/Pico SPI統合TB `+full_update`: 1024ページprogramと全256KBのFlashモデル内容照合、SPI readback、使用領域外保護、範囲/所有権/途中ページ/非整列拒否、BUSY要求拒否、timeout、CPU復帰抑止、更新後JIS1/JIS2 readがPASS。errors/warnings 0。
- 既存SPI `test_002`: スクリプト指定の1ns分解能で61 PASS / 0 FAIL。既存の未接続TB port warning 10件は残る。
- system test005/test006: バス安全性、10回BIOS CPU切替・レジスタ復元、SP診断、CPU/Pico request再受付がPASS。
- VDP logger/SPI回帰はPASS (logger本体warnings 0、SPI側既存port warning 3件)。Controller_001のWSL `make -j` は成功。
- Gowin 1.9.12.03合成・PnR・bitstream生成完了。最悪setup slack +0.207ns、hold +0.192ns。Logic 53%、register 23%、BSRAM 30/56 (54%)、latch 0。SDC/device条件は変更していない。
- 更新前bitstream・レポートはTEMPの `FPGA_MSXtR_before_serialrom_write_20261008_192314` へ退避。

実機でPicoからSerialROMを書き込み、全域verifyを通し、Z80/R800から漢字を読み出す確認は未実施。FPGAとPicoの両方を更新し、7キーの漢字単独更新から確認する。

## 2026-10-08 夜 漢字ROMの連続readとZ80/R800完了待ち

ユーザーが実機で7キーの書き込み後にR800から漢字を読んだところ、DFhが繰り返し返り、読み出しを続けるとハングした。
従来のR800 I/O経路はSerialROMの応答前に外部サイクルとして終了し、遅れて届く応答を別サイクル中にも取り込める構造だった。
Z80にも通常I/O終端でslot dataへフォールバックする処理があり、両CPUで内部漢字readの完了待ちが必要と判断した。
以前の「127clock以内ならよい」という判断は内部memory経路の上限との混同であり、I/O応答待ちを保証していなかった。

### 実装

- ユーザー指定どおり、D8h/DAh writeはCPU側SPIのどの送信状態からでもCSをHigh、SCLKをLowへ戻す。
- D9h/DBh writeでFAST_READ command/address/dummyを送り、準備完了後もCSをLowに保持する。
- D9h/DBh readは8bitだけ転送し、CSをLowのまま維持。FPGA側アドレスもincrementし、SerialROMへアドレスを再送しない。
- JIS1/JIS2交互の1byte readには対応しない。切替時にはlow/high address portの両方を設定し直す。
- Pico所有への切替とMSX resetでCPU streamを終了。Pico直接read/program/eraseは従来の独立transactionとして維持する。
- R800のD8h-DBh I/Oを内部完了待ちへ分岐し、127clockのfallback対象から除外した。
- Z80は漢字read応答まで内部WAITを保持し、I/O終端で外部slot dataへ打ち切る処理を抑止した。外部カートリッジI/Oのタイミングは変更しない。

### 検証

- 実CPUの回帰を既存Kanji TBへ追加。修正前R800では最初のINが外部モデルのDFhを返す失敗を再現した。
- 修正後は実Z80/R800ともPASS。最初の応答を180clock遅延しても先へ進まず、8回連続JIS1 readとJIS2再設定後readを正しく実行した。errors/warnings 0。
- 単体で準備済みreadが24clock以内、32byteのglyph readでheader再送なし、送信中D8 recovery、Pico切替/reset時CS解放を確認。
- `+full_update`でPicoの1024ページ更新・全域モデル照合・SPI readbackと既存の保護テストがPASS。
- Z80/R800外部memory/I/O timing、system test005/test006のバス安全性・BIOS CPU切替がPASS。旧R800 timing TBのmain_rom_cs接続を現行rom0_csへ修正して検証した。
- Gowin合成・PnR・bitstream生成は完了したが、setup違反2件、最悪slack -0.104ns。該当パスはu_ssram/ff_state_2からw_state_tick経由の内部経路。hold最悪+0.180ns、違反0。
- Logic 54%、register 23%、BSRAM 30/56 (54%)、latch 0。SSRAM RTL、SDC、デバイス設定は変更していない。更新前bitstream/レポートはTEMPへ退避済み。

機能シミュレーションは通過したが、タイミング未収束のため現在の生成bitstreamは実機投入不可として扱う。
次は現行の制約を維持してPnRのsetup違反を解消し、その後FPGAを更新して実機のDFh/ハング解消を確認する。Pico firmwareとSerialROM内容の再更新は今回のCPU/stream修正だけなら不要。

## 2026-10-08 夜 漢字アドレス仕様の再確認と追加回帰

ユーザーが合成パラメータを変更し、前節のタイミング違反を解消したと報告。実機でD9hからDFh以外が読めるようになった一方、CALL KANJIの文字崩れとSCREEN5のPUTKANJI(0,0),4321h,15によるハングが残った。
この報告は今回の追加修正前の構成に対するものであり、追加修正後のタイミング・実機結果はまだ未確認。

- 手元のkanji.romと元a1stkfn.romはいずれも256KBで、内容が完全一致した。SDカード上の実ファイルについては今回直接確認していない。
- 実a1stkdr.romに通常INだけでなくINIR、およびOUT(C),L / ADD HL,HL x2 / OUT(C),Hによる漢字アドレス設定列があることを確認。
- 既存の実CPU TBを拡張し、両CPUで32byte INIR-to-RAMと間接OUTの列を実行。これらは修正前にもPASSし、今回の実機ハング自体は再現できていない。
- openMSXのMSXKanji実装とも照合し、DAhの6bit columnはD8hと同じく5bit左シフトする必要があること、D9h/DBh writeも文字内counterを0へ戻すことを確認。従来コードはJIS2のshiftが欠落し、high writeに古いcounterが残っていた。
- 仕様ベースのテストで、D9hのみ再設定後に先頭ではなく3byte目を読む失敗 (期待85h、実値87h) とJIS2アドレス違いを検出。RTLでDAh shift、両high-port write時のcounter clear、内部counterの5bit更新を修正した。
- 新回帰では両high-port再設定、JIS2 physical address、内部counterからglyph addressへcarryしないことを検査。両CPUの間接OUT/INIRも通常run.batに登録。全5 test runsはPASS、errors/warnings 0。
- ModelSimの終了コードだけではFatalを見落とすケースがあったため、run.batはログのFatal/Errorも検査する。

JIS1全体の文字崩れとPUTKANJIハングがこれだけで解消するとは断定しない。連続SPIの方式とCPU WAITは維持し、ユーザーが調整した合成条件・SDCには手を加えていない。今回はPnRとbitstream生成を再実行していない。
次の実機切り分けでは、D8h=96/D9h=32でphysical 10400hを指定し、先頭8byteが00 00 20 10 08 04 02 01となるか、Z80/R800で比較する。新RTLは現行の合成条件で再合成・タイミング確認後にFPGAへ反映する。

### 追加の実機結果とRAM経路の回帰

ユーザーがR800モードでphysical 10400hの先頭8byteを確認し、00 00 20 10 08 04 02 01が期待通り読めた。
一方、R800のCALL KANJIでは全文字が崩れ、PUTKANJI(0,0),4321h,15でハングする。Z80ではCALL KANJIの半角16dot文字は正常表示し、ひらがな入力時にハングする。
この観測は直接readの改善を確認するが、連続read全域や描画ルーチン全体の正常動作を保証しない。

実ROMではフォントをF806hへINIRで取り込むため、既存Kanji CPU TBへ実r800_cache、ssram、SerialSRAM chip modelを接続した。
Z80のsingle SRAM access、R800のcache経由で、間接OUT、32byte INIRによるF806h buffer書込み、buffer全byte読戻し比較を確認。通常run.batに追加し、全7 test runsがPASS、errors/warnings 0。
RAM物理アドレスはTB内の単純なidentity mappingであり、実機のslot/mapper全体やVDPへの描画、CALL KANJI/PUTKANJI全処理は再現していない。

今回はTB/run.batだけを変更し、RTL・合成条件・生成bitstreamには変更なし。実機ハングの根本原因は未確定。
次にハング直後の3キーdiagnosticを複数回採取する。MENUによる所有権変更は行わず、選択CPUのPC・bus address・slot mapping・link patternを比較し、停止命令が漢字read、RAM、VDP待ち、別の処理のどれかを切り分ける。

### VDPステータス待ちの観測と漢字/VDP混在テスト

R800の実機ログではPCが2BF7h-2BFEh付近を反復し、RAM cache hitは増加、miss/fill_waitは一定だった。
A8=F3h/SSL3=09hからpage0はSLOT#3-1 EXT-ROMであり、MAIN-ROMの同PCでは解釈できない。
a1stext.romの2BF8hはIN A,(99h)、周辺はVDP status readの選択・保存・選択解除で、E28Dh/E28Ehのstack accessとも整合した。
status #2のCE待ちは有力だが、このroutineには他のcallerもあり、PCログだけで待機flagは確定していない。
ユーザーは正常なZ80/漢字ROM搭載MSXにV9968を取り付け、PUTKANJIが正常表示して戻ることを確認。本機CPU側の応答残留/VDP read混入を検証することにした。

- 既存tb_cpu_kanjiにmixed_ioを追加。漢字32byteを読む間に外部99h readを32回挟み、VDP役の20h/21h交互応答と全CPU受信値を検査。
- 外部VDP readは内部bus_ready/rdata_enで返さず、CPUの/IORQ・/RDとslot_dataで応答する。最初の漢字応答には既存の180clock遅延を維持。
- VDP read中の漢字/internal応答、SerialROM clock、受信値の取り違えをassert。漢字の続きとJIS2再設定後readも検査する。
- 次にVDP_Stack_002の実msx_slot RTLを接続し、CPU約42.95MHz、VDP約85.9MHz、serial約214.77MHzの比率で実行。VDP内部busのstatus返信だけをモデルとし、同期・応答保持・双方向data driveを通した。
- 簡易外部モデル/実VDP slot receiverとも、Z80/R800の全4混在ケースがPASS。漢字応答の残留、VDP値の混入、CPU/VDP同時driveは検出されなかった。
- 故障注入inject_staleでは、VDP readに直前の漢字値85hを返し、期待20hとの不一致を最初のreadで検出。通常の検査がデータ混入を検出できることを確認。
- 全11 regression runsを通常run.batへ登録し、errors/warnings 0で通過。RTL本体・合成条件・bitstreamは変更していない。

このテストでは実機のハングは再現できていない。VDP command engine、実ROMの描画全処理、基板/level shifterの電気的遅延は対象外であり、実機でのVDP read異常やコマンド未完了を否定しない。

## 2026-10-08 作業終了・翌日の再開点

就寝のため、本日の作業はここで中断する。以下は今日の到達点と、翌日に引き継ぐ未解決事項の要約。

### 今日の到達点

- 漢字ROMを専用SerialROMへ分離し、Picoから先頭256KBのread/program/eraseと全域verifyを行うI/Fを追加した。7キーで漢字のみ更新、ROM1への漢字書込みは廃止。
- CPU漢字readを連続SPIへ変更。D8h/DAh writeでCS Highへ復帰、D9h/DBh writeでcommand/address/dummyを送信し、read後はCS Lowを維持する。Z80/R800には漢字readの完了待ちを追加。
- JIS2 columnのshift欠落と、high-port再設定時の文字内counter残留を修正した。
- 実機ではR800でphysical 10400hの先頭8byteが期待値00 00 20 10 08 04 02 01と一致。Z80のCALL KANJIでは半角文字が正常表示することを確認した。
- ModelSimではPico全域更新、実CPUの通常IN/間接OUT/INIR、F806hへの実SerialSRAM buffer転送、漢字/外部VDP混在readを検証した。最終の通常回帰は11ケースすべてPASS、errors/warnings 0。
- ユーザーが合成パラメータ変更でタイミング違反を解消したと報告。調整した条件とSDCは維持する。こちらでは後続の追加修正後にPnRを再実行していない。

### 未解決の実機症状

- R800: CALL KANJIで文字全体が崩れ、SCREEN5のPUTKANJI(0,0),4321h,15でハングする。
- Z80: 半角は正常だが、ひらがな入力時にハングする。
- R800は完全停止ではなく、EXT-ROMのVDP status read付近を反復している。PCだけではstatus番号、CE/TR等の待機flagを確定できない。
- 正常なMSX+V9968では同じPUTKANJIが成功する。一方、本機の漢字応答残留/VDP read混入は、今回の混在テストでは再現できなかった。V9968単体の正常動作と本機の接続・アクセスの正常性は区別する。

### 明日の解析方針

- 実機で待っているVDP status番号と実値、またはstatus read routineの呼び出し元を特定する。status誤読と、実際のcommand/transfer待ちを分けることを優先する。
- Picoからstatusを読む診断を追加する場合は、バス所有権変更とR#15変更・status readの副作用を明確にし、手順と復元方法を決めてから実装する。今日はその診断は追加していない。
- 必要に応じてTBを実ROMの描画アクセス列やVDP command engineへ広げる。既存の混在・RAM・CPU回帰を利用し、未再現の原因を推測だけでRTL変更しない。
- 稼働中のSSRAM/cache、ユーザー調整済み合成条件、SDCへ解析目的の変更を加えない。観測回路を追加する場合は影響範囲とタイミングを別途評価する。
- ROM1をSLOT#1のメガROMとして使うモードは未実装のまま。現在の漢字描画問題とは別の次作業として残す。

今回は記録の追記だけを行い、追加テスト・コード変更・commit/pushは行わず終了する。
