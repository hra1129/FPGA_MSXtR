# PPI

`ppi.v` は、MSX turbo R CPU stack 向けの i8255 相当の Programmable Peripheral Interface です。

## クロックとリセット

- `clk` は 42.9545 MHz で動作します。
- `reset_n` はアクティブLowの同期リセットです。
- リセット時、Primary slot は `8'hFF`、キーボード行選択は `4'hF`、Port C の出力はすべて `1` になります。

## 内部バス

| 信号 | 説明 |
| --- | --- |
| `bus_cs` | PPI選択信号 |
| `bus_address[1:0]` | PPIポート選択 |
| `bus_io` | I/Oアクセス種別 |
| `bus_write` | `1` で書込み、`0` で読出し |
| `bus_wdata[7:0]` | 書込みデータ |
| `bus_valid` | バスアクセス有効 |
| `bus_ready` | 常に `1`。ウェイトなしで応答 |
| `bus_rdata[7:0]` | 読出しデータ |
| `bus_rdata_en` | 読出しデータ有効。読出しアクセスのクロック後に `1` |

書込みは `bus_cs && bus_valid && bus_write`、読出しは `bus_cs && bus_valid && !bus_write` のときに受け付けます。

## ポートマップ

| `bus_address` | ポート | 書込み | 読出し |
| --- | --- | --- | --- |
| `2'b00` | Port A | `primary_slot` を更新 | `primary_slot` |
| `2'b01` | Port B | なし | 選択中キーボード行の `keyboard_matrix` |
| `2'b10` | Port C | キーボード行、カセット、LED、1bit音源を更新 | 現在のPort C出力値 |
| `2'b11` | コマンド | Port Cの指定ビットを更新 | `8'hFF` |

## Port A

`primary_slot[7:0]` は主スロット選択レジスタです。Port Aへの書込み値がそのまま出力されます。

## Port Bとキーボード行列

`keyboard_matrix_valid` が `1` のクロックで、`keyboard_matrix_row[3:0]` で示す行に `keyboard_matrix[7:0]` を取り込みます。Port Cの下位4bitで選択された行をPort Bから読出します。未更新の行はリセット後 `8'hFF` です。

## Port C

Port Cの各ビットは次の通りです。

| bit | 信号 | 説明 |
| --- | --- | --- |
| 7 | `one_bit_sound` | 1bit音源出力 |
| 6 | `keyboard_caps_led` | Caps LED出力 |
| 5 | cassette write | カセット出力 |
| 4 | cassette motor | カセットモーター制御 |
| 3:0 | keyboard row | キーボード行選択 |

Port C (`2'b10`) への書込みで全ビットを更新できます。コマンドポート (`2'b11`) への書込みでは、`bus_wdata[3:1]` でビット番号を選び、`bus_wdata[0]` をそのビットへ書き込みます。

## テスト

`test_001/run.bat` は ModelSim の `vlog` と `vsim` を使い、リセット、ポートA、Port C、キーボード行列、および読出し有効信号を検証します。