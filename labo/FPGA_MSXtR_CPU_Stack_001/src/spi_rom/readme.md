# ip_spi_rom

## 概要

SPI シリアルフラッシュ ROM コントローラ。  
内部バスインタフェース経由でコマンドポートとデータポートを操作することで、
シリアルフラッシュ ROM の読み出し・書き込み・消去などを行う。

---

## ファイル構成

| ファイル名 | 説明 |
|---|---|
| ip_spi_rom.v | SPI ROM コントローラ本体 |

---

## モジュール: ip_spi_rom

### ポート一覧

| ポート名 | 方向 | 幅 | 説明 |
|---|---|---|---|
| reset | input | 1 | システムリセット (Active High) |
| clk | input | 1 | システムクロック |
| clk_serial | input | 1 | シリアルクロック (高速クロック) |
| bus_cs | input | 1 | バスチップセレクト |
| bus_address | input | 1 | バスアドレス (0: コマンドポート / 1: データポート) |
| bus_write | input | 1 | バスライト (1: ライト / 0: リード) |
| bus_valid | input | 1 | バスアクセス有効 |
| bus_ready | output | 1 | バスレディ (1: 受付可能 / 0: ビジー) |
| bus_wdata | input | 8 | バス書き込みデータ |
| bus_rdata | output | 8 | バス読み出しデータ |
| bus_rdata_en | output | 1 | バス読み出しデータ有効 (1クロックパルス) |
| srom0_cs_n | output | 1 | シリアルROM 0 チップセレクト (Active Low) |
| srom1_cs_n | output | 1 | シリアルROM 1 チップセレクト (Active Low) |
| srom_clk | output | 1 | QSPI クロック |
| srom_sio | inout | 4 | QSPI シリアルデータ (双方向 4bit) |

---

## バスインタフェース

`bus_address` によってポートを選択する。

| bus_address | 説明 |
|---|---|
| 0 | コマンドポート |
| 1 | データポート |

### アクセス手順

1. `bus_cs=1` / `bus_valid=1` のタイミングでアクセスを発行する。  
2. `bus_ready=0` の間はバスはビジー状態。次のアクセスは `bus_ready=1` になるまで待つ。  
3. リードアクセスの場合、`bus_rdata_en=1` のサイクルに `bus_rdata` が有効となる。

---

## コマンド一覧

コマンドポート (`bus_address=0`) に以下の値を書き込むことでコマンドを設定する。

| コマンド値 | コマンド名 | 説明 |
|---|---|---|
| 0x00 | SET ADDRESS | アドレスセットモードに切り替える。続けてデータポートへ 3byte (MSB順) を書き込むと、24bitアドレスがセットされる。 |
| 0x01 | SINGLE READ | 1byteリードモード。データポートをリードするたびにアドレスを発行し、1byte 読み出す。アドレスは自動インクリメントされる。 |
| 0x02 | BURST READ | 256byteバーストリードモード。コマンド発行時にアドレスを発行する。以降のデータポートリードは 1byte ずつ読み出す。開始アドレスの下位1byteは無視される (256byte境界)。 |
| 0x03 | BURST WRITE | 256byteバーストライトモード。コマンド発行時にアドレスを発行する。以降のデータポートライトは 1byte ずつ書き込む。開始アドレスの下位1byteは無視される (256byte境界)。 |
| 0x04 | CHIP ERASE | フラッシュROM全体を消去するコマンドを発行する。データポートへのアクセスは不要。 |
| 0x05 | READ STATUS | ステータスレジスタ読み出しモード。データポートから 1byte 読み出すと、最下位ビット (bit0) が busy フラグとなる。 |
| 0x06 | SELECT SROM | 接続するシリアルROMを選択する。データポートへ ROM 番号を書き込む。 |
| 0x07 | ACCESS END | シリアルROMのアクセスを終了する。CS を非アクティブに戻す。 |
| 0x08 | SET QUAD ENABLE | シリアルROMの Quad Enable ビット (Status Register 2, bit1) をセットする。 |
| 0x09〜0xFF | (予約) | 無効。何も行わない。 |

---

## コマンド詳細

### 0x00: SET ADDRESS

- コマンドポートに `0x00` を書き込むと、アドレスセットモードになる。
- 続けてデータポートへ 3byte を LSB から順に書き込むと 24bit アドレスがセットされる。
- 途中でコマンドポートに `0x00` を再書き込みすると、1byte 目からやり直しになる。

### 0x01: SINGLE READ

- データポートをリードするたびに、`FAST READ QUAD I/O (EBh)` コマンドを発行してアドレスから 1byte 読み出す。
- 読み出し後、アドレスは自動的に +1 インクリメントされる。
- Quad SPI モードでアドレスおよびデータを転送する。

### 0x02: BURST READ

- コマンド発行時点で `FAST READ QUAD I/O (EBh)` コマンドとアドレスを発行する。
- 開始アドレスの下位 8bit は `0x00` に強制される (256byte 境界)。
- 以降のデータポートリードは Quad SPI リードで 1byte ずつ読み出す (CS はアクティブを維持)。
- `ACCESS END (0x07)` を発行するまで CS はアクティブのままとなる。

### 0x03: BURST WRITE

- コマンド発行時点で `WRITE ENABLE (06h)` → `PAGE PROGRAM (02h)` + アドレスを発行する。
- 開始アドレスの下位 8bit は `0x00` に強制される (256byte 境界)。
- 以降のデータポートライトは Standard SPI ライトで 1byte ずつ書き込む (CS はアクティブを維持)。
- `ACCESS END (0x07)` を発行するまで CS はアクティブのままとなる。

### 0x04: CHIP ERASE

- `WRITE ENABLE (06h)` → `CHIP ERASE (60h)` の順にコマンドを発行する。
- 完了後、CS を非アクティブにする。

### 0x05: READ STATUS

- `READ STATUS REGISTER-1 (05h)` コマンドを発行する。
- データポートから 1byte 読み出すと、`bus_rdata[0]` に busy フラグ (S0) が返る。
- CS はアクティブを維持し、`ACCESS END (0x07)` まで継続リードが可能。

### 0x06: SELECT SROM

- データポートへ書き込む値によって、アクティブにするチップセレクトを選択する。

| 書き込み値 | 動作 |
|---|---|
| 0x00 | srom0_cs_n をアクティブ (srom1_cs_n は非アクティブ) |
| 0x01 | srom1_cs_n をアクティブ (srom0_cs_n は非アクティブ) |
| 0x02〜0xFE | (予約) |
| 0xFF | 両方非アクティブ (未接続) |

### 0x07: ACCESS END

- `w_serial_idle` が 1 になるのを待ってから、CS を非アクティブ (1) に戻す。

### 0x08: WRITE ENABLE

- `WRITE ENABLE (06h)` コマンドを発行し、書き込みを許可する。
- STATUS READ コマンドで、ステータスレジスタの bit 1 が 1 になるまで待機すること。

### 0x09: BLOCK ERASE

- SET ADDRESS で指定したアドレスに対応するブロックを消去して、全bit 1 にする。

---

## CS 制御とウェイト

| 状況 | CSウェイト |
|---|---|
| BURST READ / READ STATUS 終了後 | 約 10ns (CS_WAIT_10NS = 1クロック) |
| その他のコマンド終了後 | 約 50ns (CS_WAIT_50NS = 5クロック) |

---

## シリアルROM ステータスレジスタ (参考)

| ビット | 名称 | 説明 |
|---|---|---|
| S0 | BUSY | 書き込み/消去処理中 |
| S1 | WEL | ライトイネーブルラッチ |
| S2〜S4 | BP[2:0] | ブロックプロテクトビット |
| S5 | TB | トップ/ボトムライトプロテクト |
| S6 | SEC | セクタプロテクト |
| S7 | SRP0 | ステータスレジスタプロテクト 0 |
| S8 | SRP1 | ステータスレジスタプロテクト 1 |
| S9 | QE | Quad Enable |
| S10〜S15 | - | 予約 |

---

## 使用するシリアルROM コマンド

| コマンド | 値 | 説明 |
|---|---|---|
| PAGE PROGRAM | 0x02 | 1ページ (256byte) 書き込み |
| WRITE DISABLE | 0x04 | ライト禁止 |
| READ STATUS REGISTER-1 | 0x05 | ステータスレジスタ1 読み出し |
| WRITE ENABLE | 0x06 | ライト許可 |
| READ STATUS REGISTER-2 | 0x35 | ステータスレジスタ2 読み出し |
| WRITE STATUS REGISTER-2 | 0x31 | ステータスレジスタ2 書き込み |
| CHIP ERASE | 0x60 | 全消去 |
| FAST READ QUAD I/O | 0xEB | Quad I/O 高速リード |

---

## サブモジュール: qspi

### 概要

Quad SPI の物理層コントローラ (Mode 0 のみ対応)。  
Standard SPI / Quad SPI の読み書き、ダミークロック出力をサポートする。  
Dual SPI は非対応。

### シリアルモード

| モード値 | モード名 | 説明 |
|---|---|---|
| 0 | MODE_STD_WRITE | Standard SPI ライト (MOSI 1bit) |
| 1 | MODE_STD_READ | Standard SPI リード (MISO 1bit) |
| 2 | MODE_QUAD_WRITE | Quad SPI ライト (SIO 4bit 出力) |
| 3 | MODE_QUAD_READ | Quad SPI リード (SIO 4bit 入力) |
| 4 | MODE_QUAD_DUMMY | Quad SPI ダミークロック (1byte 分) |
| 5 | MODE_QUAD_DUMMY2 | Quad SPI ダミークロック (2byte 分) |
| 6〜7 | (予約) | - |
