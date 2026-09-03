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
