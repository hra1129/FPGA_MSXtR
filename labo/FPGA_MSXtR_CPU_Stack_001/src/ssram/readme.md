# Serial SRAM access module

## 概要

`ssram.v` は、Quad I/O 対応の Serial SRAM をアクセスするためのモジュールです。
1 個あたり 512 KiB の Serial SRAM を 4 個接続し、4 個を連続した 2 MiB のメモリ空間として扱います。

4 個の SRAM は `sram_sio[3:0]` と `sram_sclk` を共有します。アクセスする SRAM は、バスアドレスの上位 2 bit で選択します。

## モジュールインターフェース

```verilog
module ssram (
    input           n_reset,
    input           clk,
    input           clk_serial,
    input           bus_cs,
    input  [21:0]   bus_address,
    input           bus_write,
    input           bus_valid,
    input  [7:0]    bus_wdata,
    output          bus_ready,
    output [7:0]    bus_rdata,
    output          bus_rdata_en,
    output          sram_sclk,
    output          sram_ce0_n,
    output          sram_ce1_n,
    output          sram_ce2_n,
    output          sram_ce3_n,
    inout  [3:0]    sram_sio
);
```

### バス信号

| 信号 | 方向 | 幅 | 説明 |
|---|---|---:|---|
| `n_reset` | input | 1 | Low active reset |
| `clk` | input | 1 | バス側クロック |
| `clk_serial` | input | 1 | Serial SRAM 側クロック。内部で SCLK を分周して生成 |
| `bus_cs` | input | 1 | バスアクセス選択 |
| `bus_address` | input | 22 | 4 x 512 KiB = 2 MiB の論理アドレス |
| `bus_write` | input | 1 | `1`: write、`0`: read |
| `bus_valid` | input | 1 | アクセス要求有効 |
| `bus_wdata` | input | 8 | write データ |
| `bus_ready` | output | 1 | 新しい要求を受け付け可能 |
| `bus_rdata` | output | 8 | read データ |
| `bus_rdata_en` | output | 1 | read データ有効パルス |

### Serial SRAM 信号

| 信号 | 方向 | 幅 | 説明 |
|---|---|---:|---|
| `sram_sclk` | output | 1 | 4 個の SRAM で共有する Serial Clock |
| `sram_ce0_n` | output | 1 | SRAM0 の Chip Enable、Low active |
| `sram_ce1_n` | output | 1 | SRAM1 の Chip Enable、Low active |
| `sram_ce2_n` | output | 1 | SRAM2 の Chip Enable、Low active |
| `sram_ce3_n` | output | 1 | SRAM3 の Chip Enable、Low active |
| `sram_sio` | inout | 4 | 4 個の SRAM で共有する Quad I/O データ線 |

## アドレスマップ

各 Serial SRAM は 512 KiB = `0x80000` bytes です。

| `bus_address[21:20]` | 論理アドレス範囲 | 選択される SRAM | CE |
|---|---|---|---|
| `2'b00` | `0x000000` - `0x07FFFF` | SRAM0 | `sram_ce0_n = 0` |
| `2'b01` | `0x080000` - `0x0FFFFF` | SRAM1 | `sram_ce1_n = 0` |
| `2'b10` | `0x100000` - `0x17FFFF` | SRAM2 | `sram_ce2_n = 0` |
| `2'b11` | `0x180000` - `0x1FFFFF` | SRAM3 | `sram_ce3_n = 0` |

各 SRAM に送信する内部アドレスは `bus_address[18:0]` です。

```text
bus_address[21:20] : SRAM 選択
bus_address[18:0]  : 選択した SRAM 内のアドレス
```

`bus_address[19]` はこのモジュールでは使用しません。2 MiB の有効アドレス範囲は `0x000000` から `0x1FFFFF` までです。

## CE の動作

- リセット中および初期化中は、4 本の CE をすべて High にします。
- Serial SRAM へのアクセス中は、選択された SRAM の CE だけ Low にします。
- 選択されていない SRAM の CE は High のままです。
- `sram_sclk` と `sram_sio` は 4 個の SRAM で共有します。
- アクセス終了時には CE を High に戻します。

## 初期化

リセット解除後、約 100 us の待機時間を置いてから、Serial SRAM に `EQIO`（`0x38`）コマンドを送信します。
これにより、SRAM を Quad I/O モードへ移行させます。

初期化が完了するまでは `bus_ready` は Low です。初期化完了後、`bus_ready` は High になり、通常の read/write 要求を受け付けます。

## Write 動作

Quad I/O モードで、次の形式のアクセスを行います。

```text
Command : 0x02 (Quad Write)
Address : bus_address[18:0]
Data    : bus_wdata
```

実際の Serial SRAM への送信単位は 4 bit です。

```text
1 nibble  : 0x0
1 nibble  : 0x2
6 nibbles : 19 bit address
2 nibbles : 8 bit write data
```

## Read 動作

Quad I/O モードで、次の形式のアクセスを行います。

```text
Command : 0x0B (Quad Fast Read)
Address : bus_address[18:0]
Dummy   : 3 nibble cycles
Data    : 8 bit read data
```

read データを受信すると、`bus_rdata` にデータを出力し、`bus_rdata_en` を 1 クロック幅のパルスとして出力します。

## バスアクセスの流れ

### Write

1. `bus_cs && bus_valid && bus_ready` が成立すると要求を受け付けます。
2. `bus_address[21:20]` から SRAM を選択します。
3. `bus_address[18:0]` と `bus_wdata` を Serial SRAM 側クロックドメインへ渡します。
4. Quad Write を実行します。
5. CE を High に戻し、`bus_ready` を再び High にします。

### Read

1. `bus_cs && bus_valid && bus_ready` が成立すると要求を受け付けます。
2. `bus_address[21:20]` から SRAM を選択します。
3. `bus_address[18:0]` を送信します。
4. 3 nibble の dummy cycle の後、データを受信します。
5. `bus_rdata_en` を出力し、CE を High に戻します。
6. `bus_ready` を再び High にします。

## クロックドメイン

バス要求は `clk` ドメインで受け付け、トグル信号を使って `clk_serial` ドメインへ通知します。

- `clk`: バスインターフェース、要求受付、`bus_ready`
- `clk_serial`: Quad I/O コマンド生成、SCLK 生成、データ送受信

要求アドレス、write/read、write データは `clk` 側でラッチし、Serial SRAM 側で要求通知を検出した後に使用します。

## 注意事項

- `bus_address[19]` は未使用です。上位 2 bit を SRAM 選択に使うため、論理アドレスは 2 MiB 範囲で使用してください。
- 4 個の SRAM の `CE` は個別ですが、`sram_sclk` と `sram_sio` は共有です。
- `ssram.v` の `sram_ce0_n`～`sram_ce3_n` は Low active です。
- トップレベルで使用する場合は、4 本の CE を対応する FPGA 外部ポートへ接続してください。
- 初期化中に SRAM へアクセスしないでください。`bus_ready` が High になるまで要求を待つ必要があります。
