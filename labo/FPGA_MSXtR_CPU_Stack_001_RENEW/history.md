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
