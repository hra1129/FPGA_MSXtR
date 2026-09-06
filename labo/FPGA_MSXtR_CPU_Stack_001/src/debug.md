# SerialSRAM (ssram) 実機動作不良 デバッグ状況

2026-09-05 時点の状況まとめ。翌日のシミュレーション波形確認のための基礎資料。

## 症状

- 実機 (新基板, 4チップ QSPI-SRAM 搭載) で SerialSRAM テスト (Pico ファーム 9キー) が **全滅** (fail=49152)
- テスト内容: 0x4000-0xFFFF に 00-FF を書いて読み出し比較 (page1-3, mapper セグメント1-3 → 全て chip0 内 64KB 範囲)
- シミュレーション (test_001) では **全 11 テスト PASS** している
- 1チップ構成の旧基板では読み書き成功実績あり (clk=42.95454MHz / clk_serial=214.7727MHz 同一)

## 現在の構成

### トップ接続 (FPGA_MSXtR_CPU_Stack.v)
- `w_ssram_address[20:0] = { w_mapper_segment[6:0], w_device_address[13:0] }`
- ssram bus_address[20:0]: [18:0]=チップ内アドレス(512KB), [20:19]=チップ選択
- address_decode: `ssram_cs = ~device_io & (device_address[15:14] != 2'd0)` (page1-3)
- Pico テストはセグメント1-3設定なので SRAM アドレス 0x004000-0x00FFFF (chip0 のみ使用)

### ssram.v 現在の状態 (ワークツリー)
1. **EQIO 初期化**: `c_state_init_w0` (100us 待機) → `eqio0..7` で 0x38 送信。
   - `w_eqio_active` = (eqio0..7) の間、**全4チップの CE を同時アサート**して一斉送信
   - 完了後 `c_state_idle` へ (ff_active=1)
2. **読み出し**: dummy0-5 (6ニブル) →
   - HW: `c_state_read_wait` 1ニブル追加 → read0 (上位サンプル) → read1 (下位サンプル) → read2 (CE上昇) → read3
   - SIM: read_wait スキップ。read0 (上位) → read2 (下位: `ifdef SIM で read2 に遅延) → read3
3. **書き込み**: address5 後 write0 (上位), write1 (下位) → idle

## これまでの修正 (全てワークツリーに反映済み)

1. アドレス幅 [21:0]→[20:0] 修正 (2MB=2^21)。旧は chip2/3 到達不能バグ
2. EQIO を全チップ一斉送信に変更 (旧: chip0 のみ)
3. SIM 用サンプリング read1→read2 遅延 (合成には無関係)
4. Gowin プロジェクト (.gprj) に memory_mapper.v 登録

## 現在の主要な疑いポイント

### A. 実機とシミュレーションの読み出しタイミング差 (最重要)

| | SIM (PASS 確認済み) | HW (実機, 未検証) |
|---|---|---|
| dummy 後 | dummy5 → read0 直接 | dummy5 → **read_wait 1ニブル追加** |
| 上位ニブル サンプル | read0 の SCLK 立上がり | read0 の立上がり (SIM より 1 SCLK 遅い) |
| 下位ニブル サンプル | read2 | read1 |

**問題**: HW パスはシミュレーションで一度も検証されていない (テストは `+define+SIM` でコンパイルするため read_wait がスキップされる)。
チップ (LCSC C27585175 = QSPI-SRAM 4Mbit) の tV (clock-to-valid) が SCLK 半周期 (~5ns) 未満なら、HW の「1ニブル遅れ」はデータシート上のデータを取りこぼす。

**確認したい波形**:
- read_wait ありの HW パスでの sram_sclk / sram_sio / ff_state / ff_rdata の関係
- チップがデータを駆動するタイミング vs DUT のサンプリングエッジ

### B. EQIO が実機チップに届いているか

- 一斉送信に変更したが、実機で CE 全 Low + 8 クロックの 0x38 フレームが出ているか未確認
- EQIO が届かなければ quad モードに入らず全アクセス失敗 (「全滅」と一致)
- チップの電源投入直後の状態 (SPI モード) と、FPGA リセット時の再 EQIO の挙動も確認ポイント

### C. 基板・配線

- 動作実績は旧基板 (1チップ)。新基板 (4チップ) は未検証
- .cst: ce0=L4, ce1=L3, ce2=J1, ce3=J2, sclk=F2, sio[3:0]=D1,E1,A1,F1
- 新基板の実配線との一致を確認 (HEAD コミット "A14, A15 pin assign" 修正の経緯あり)
- 4チップ接続による配線容量増加で SCLK/SIO の波形劣化の可能性

## シミュレーションで明日確認すべきこと

1. **HW パス (`SIM` 未定義) での読み出し波形**:
   - `vlog ..\ssram\ssram.v` (define 無し) でコンパイルし、read_wait 経路の波形を確認
   - モデル側の駆動タイミング (count==14/15) と DUT のサンプリング (read0/read1) のずれを可視化
2. **EQIO 一斉送信の波形**: sram_ce0-3_n が同時に Low になり、8 クロックの 0x38 パターンが sram_sio[0] に出ているか
3. **実機パラメータとの整合**: チップデータシートの tV, tHZ, セットアップ/ホールド時間と、現在の SCLK タイミング (100.226MHz) の関係

## 関連ファイル

- [ssram.v](ssram/ssram.v) — DUT 本体
- [ssram_test_model.v](ssram/ssram_test_model.v) — 512KB/chip の正規シミュレーションモデル
- [memory_mapper.v](memory_mapper/memory_mapper.v) — ページ→セグメント変換
- [address_decode.v](address_decode/address_decode.v) — bootrom(page0)/ssram(page1-3)/ppi/mapper の CS 生成
- [test_001/tb.sv](test_001/tb.sv) — テストベンチ (TEST 10=mapper, TEST 11=ssram 経由メモリアクセス)
- [test_001/run.bat](test_001/run.bat) — コンパイル・実行スクリプト
- リポジトリメモリ: /memories/repo/cpu_stack001_memory_mapper.md, /memories/repo/cpu_stack001_ssram_read_timing.md
