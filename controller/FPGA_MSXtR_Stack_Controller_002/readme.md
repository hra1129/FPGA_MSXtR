# 環境設定
	環境変数 PICO_SDK_PATH に、https://github.com/raspberrypi/pico-sdk を clone したパスを指定しておく。
	WSLでやるなら、 WSL側の環境変数に WSL側のパスで記入すること。

	cd {SDKパス}
	git clone https://github.com/raspberrypi/pico-sdk
	setx PICO_SDK_PATH={SDKパス}

# ビルド
	cmake --build build --target fpga_msxtr_controller
	cmake -S . -B build -DPICO_BOARD=pico2

## Keyboard/UIモードとバス所有権

MENUキーはkeyboard matrixの転送先だけを切り替える。CPU/Picoのバス所有権は通常CPUに残し、MENU操作では変更しない。

- 起動時にMENUを押していなければkeyboard forwardingを有効にする。起動時にMENUを押していればPico-local modeで起動する。
- 実行中のMENUでkeyboard forwardingとPico-local modeを切り替える。Pico-localへ切り替える際は、FPGAへ全キーreleaseを送る。
- Pico-local modeでは以下の操作メニューを1行1項目で表示する。2/3/4キーの更新処理と5/6/7キーの診断は、実行中だけPicoへバス所有権を移し、終了後CPUへ戻す。
- 1キーのCPU debug表示はSPI診断読出しだけを行い、所有権を切り替えない。keyboard forwarding中の3キーdebug表示と7キーVDP log切替は従来どおり。
- command完了後にCPU所有権へ戻せなかった場合はPico所有を維持し、エラーを表示する。SerialROMが未照合の場合もCPU復帰を拒否する。

```text
1: CPU debug
2: BIOS update
3: ExtROM update
4: KanjiROM update
5: KanjiROM glyph test
6: MapperRAM test
7: KOEI slot/RAM diagnostic
8: Slot trace dump
9: Slot trace clear/re-arm
D: Disk mode toggle (image /DSK/2DD.DSK <-> SD direct)
```

Pico-local modeで5キーを押すと、JIS1 `3441h` (漢) のD8=`A1h`/D9=`16h`に対応するSerialROM物理アドレス`0B420h`から32byteを読み、OpenMSXの漢字ROM配列と同じく先頭8byte/次の8byteを上半分の左右byte、その次の8byte/最後の8byteを下半分の左右byteとして、各8bitの0/1表記で16行表示する。この診断はPicoのSerialROM直接readを使用するため、CPUのD8h/D9hアクセス待ちや`msx_slot`のタイミングは経由しない。ROM内容・アドレスの確認用であり、CPU read timeoutの合否判定には使わない。

Pico-local modeで7キーを押すと、現在のpage3でE3A0h-E3AFhを読み、続けてpage3をSLOT#3-0に切り替えて同じ領域を読み出す。その後、ゲームと同じ順序で各スロットの4000hに55h/AAhを書いて読み戻し、最初にRAMと判定されるスロットを表示する。テスト後はスロット選択状態を復元し、4000hには読み出した元の値を書き戻す。

## スロットトレース (8/9キー, SPI 1Ah/1Bh)

FPGA (`labo/FPGA_MSXtR_CPU_Stack2_000/src/slot_trace/slot_trace.v`) は、A8h書き込み、SLOT#0/#3のFFFFh書き込み、CPU切替、MSXリセットON/OFFを1024件のリングバッファに記録する。ログはSPIリセットでのみ消え、MSXリセットでは消えない。8/9キーはSPIアクセスだけでバス所有権は切り替えない (切り替えるとCPU切替イベントが記録されるため)。

- 起動時はトリガ有効、トリガ値 `A8h=22h`。トリガ成立後64件記録して凍結する。
- 8キー: hold (記録停止) を立てて、最古から全件を `idx time[us] CPU PC type old->new` で表示する。トリガ行には `<== TRIGGER` を付ける。holdはダンプ後も維持する。
- 9キー: ログをクリアし、トリガ `A8h=22h` で再アームする。
- type: `A8h`=primary slot、`SSL0`/`SSL3`=FFFFh書き込み (old=書込前の値)、`CPU`=cpu_sel変化 (0:Z80 1:R800 2/3:Pico)、`RST+`/`RST-`=MSXリセットON/OFF、`MAP`=マッパー書込 (old=I/Oポート、既定では記録しない)。
- timestampは約1µs単位の24bitカウンタ (約16.7秒で一周)。PCはその時点の選択CPUのPC。

| コマンド | 引数 | 応答 |
|---|---|---|
| 1Ah | idx_l, idx_h(bit1:0) | spi_intr後17byte: entry 8byte (LE: [7:4]type [3:2]cpu_sel / old / new / PC / timestamp 24bit), count 2byte, trigger index 2byte, flags (bit0 trig_en, bit1 mapper_en, bit2 hold, bit3 triggered, bit4 frozen), trigger value, 予備2byte, A5h |
| 1Bh | control, trigger value | spi_intr。control bit0 clear, bit1 trigger有効, bit2 mapper記録, bit3 hold |

## ディスクエミュレーター (Dキー, SPI 20h〜24h)

FPGA の disk_if (`labo/FPGA_MSXtR_CPU_Stack2_000/src/disk_if/readme.md`) の要求を `disk_emu.c` が処理する。SD のアクセスはすべて Core 0 で行う (Core 1 はキーボードの I2C だけ)。

- 起動時: SD のマウントと `/DSK/2DD.DSK` のオープンを行い、24h で READY/WPROT を設定してから MSX のリセットを解除する。
- 要求の検知: keyboard forwarding 中は 11h の応答 bit4、Pico-local mode 中は 05h の応答 bit3 (DISK_REQ) を 2ms ごとに見る。1 なら 20h → (READ: SD から読んで 22h / WRITE: 21h で受け取って SD に書く) → 23h。
- DSK イメージモード (起動時の既定): `/DSK/2DD.DSK` を開いたままにして `f_lseek` → `f_read` / `f_write` + `f_sync`。読み取り専用属性のファイルは WPROT=1。`/DSK/2DD.ERR` (1 セクター 1 バイト = DSKIO エラーコード) はマウント時に RAM に読む (最大 2880 セクター分)。ファイルがなければ全セクターエラーなし。flashrom の更新などで再マウントされて FIL が無効になったら、1 回だけ開き直す。
- SD 直接モード: FatFs をアンマウントし、`disk_read` / `disk_write` で SD のセクターを直接読み書きする。先頭 (パーティションなし) または MBR の最初のパーティションのブートセクターが FAT12/16 でなければ READY=0。
- Dキー (Pico-local mode): DISK_REQ=0 のときだけモードを切り替え、24h で CHANGED=1 を送る。
- FatFs は pico-sdk 同梱 (tinyusb) の ffconf.h を使っており `FF_USE_FASTSEEK=0` なので、fast seek は使っていない。

## BIOS / ExtROM更新

- 2キー: ROM0 (512KB)だけを消去・更新する。既存と同じく `/bios/msxtr.rom`、`/bios/msx2p.rom`、`/bios/msx2.rom`、`/bios/msx1.rom` の順で使用可能なBIOSを選ぶ。ROM1と漢字SerialROMは変更しない。
- 3キー: `/bios/extrom.rom` をROM1 (512KB、Pico物理ベース80000h)へ消去・更新する。ROM0と漢字SerialROMは変更しない。
- FlashROMイメージは1～524288byteに限定し、消去前に存在とサイズを確認する。各byteは書込み後に読戻し値を照合する。短いイメージの残りは消去済みFFhのままになる。

## RAMダンプ

RAMダンプは現在の4項目メニューには割り当てない。既存の `dump_cpu_ram()` はC000h～DFFFhの8192byteとE600h～E6FFhの256byteを標準出力へダンプする。先頭にCPUのPCとスロット情報、メモリを16byte/行のアドレス付き16進数で表示する。

RAMへの書き込みやリセットは行わない。呼出し側でPicoバス所有権を取得する必要がある。

DFFFhの色変数とRAM常駐コードに加え、E62Dh・E63Fh・E651hを先頭とする3レコードの判定用データも採取する。WSLでのファームウェアビルド確認済み。実機読出し確認は未実施。

## 漢字SerialROM更新 (2026-10-08)

FPGA/Picoの両方を更新する。W25Q32JVSSの先頭256KB (00000h-3FFFFh) だけを使用し、残りの領域は消去・書き込みしない。

Pico-local modeにし、SDカードに正確に262144byteの `/bios/kanji.rom` を置く。4キーのROM更新処理は必要な間だけPicoへバス所有権を移す。

- 4キー: 漢字SerialROMだけを消去・更新・全256KB照合する。ROM0/ROM1は変更しない。
- 更新成功後は自動的にCPU所有へ戻る。失敗時はPico所有を維持し、未照合のままCPUへ戻す操作を拒否する。

使用領域の全消去は64KB Block Erase (D8h)を4回実行し、4MB全体のChip Eraseは行わない。
各256byteページは全受信後にPage Program (02h)し、Write Enable (06h)のWELとStatus Register (05h)のBUSYを確認する。
ページ書き込み中の通信終了はFlash処理を中断しない。256byte未満で通信を終了したページは書き込まない。
更新は電源断に対して原子的ではない。途中で電源を切った場合は、Pico所有のmaintenance modeで再度更新する。

Pico API: `fpga_serialrom_read(address, data, length)` (1-256byte)、`fpga_serialrom_program_page(address, data)` (256byte境界)、
`fpga_serialrom_erase()` (先頭256KB)、`fpga_serialrom_get_status(&status)`。
書き込み/消去後はCPU復帰が抑止される。独自更新処理では全イメージ照合成功後にだけ `fpga_serialrom_set_verified(true)` を呼ぶ。

### SPIコマンド

アドレスは3byte little-endian。範囲外アドレスは切り捨てず拒否する。各送信byte間に1us待ち、返信byteごとにSPI_INTRを待つ。

| コマンド | 送信 | 返信 |
| --- | --- | --- |
| 15h | addr_l, addr_m, addr_h, length-1 | 完了status、成功時のみ指定byte数のdata |
| 16h | addr_l, addr_m, addr_h, data x256 | 受理status。処理完了は18hで確認 |
| 17h | なし | 受理status。処理完了は18hで確認 |
| 18h | なし | 現在のstatus |

status bit0はBUSY、bit[7:1]はerror code (0=なし、1=CPU所有、2=アドレス/長さ/ページ境界、3=BUSY中要求、4=Flash BUSY timeout、5=WEL確認失敗)。
要求拒否の返信は進行中操作のstatusを変更しない。BUSY・Flashエラー中はFPGA側もCPU所有権への切替を抑止する。
Z80/R800のD8h-DBh漢字アクセスは維持し、Pico物理readは漢字enableやJISアドレスとは独立する。MSXリセット中でもPico更新は可能。

ModelSimで1024ページ更新、全域モデル照合、SPI readback、範囲/所有権/途中通信保護、BUSY timeout、CPU復帰抑止、更新後JIS1/JIS2読出しを確認。
PicoビルドとFPGA合成/PnRは完了。実チップでの更新・照合および漢字表示は未確認。

### 漢字I/Oの連続読み出し (2026-10-08 夜)

- D8h/DAh writeでCSをHigh、SCLKをLowへ戻し、CPU側の送信中状態も終了させる。
- D9h/DBh writeでコマンド・アドレス・dummyを送信し、CSをLowに保持する。
- D9h/DBh readでは準備完了後に8bitだけ転送する。CSはLowを維持し、アドレスは再送しない。
- JIS1/JIS2切替時は必ずD8h/D9hまたはDAh/DBhを設定し直す。交互1byte readは非対応。
- Pico所有への切替またはMSX resetでCPUの連続読み出しを終了する。CPUへ戻った後は漢字アドレスを設定し直す。
- 初回readや遅い応答はZ80/R800の内部完了待ちで延長し、外部slot dataへのフォールバックで打ち切らない。

CPU/SerialROM統合テストで連続readは24clock以内、実Z80/R800で180clock遅延応答と連続INがPASS。
この修正版のPnRはSSRAM内部にsetup違反2件 (最悪-0.104ns) が残る。SSRAM/SDCは変更しておらず、タイミング解消前の実機書き込みは行わない。

その後、ユーザーが合成パラメータ変更で違反解消を確認した。追加のアドレス修正ではDAh columnをD8h同様に5bit左シフトし、D9h/DBh writeでも文字内counterを0へ戻す。
内部counterは5bitだけを更新する。連続SPIは従来どおりで、文字ごとのアドレス再設定を前提とする。
追加修正後のModelSimは両CPUのOUT(C),L/H・32byte INIRを含めPASS。PnRと実機確認は未実施で、CALL KANJI/PUTKANJIの不具合解消は未確認。

## DIPSW (Pico GPIO16-19)

`dipsw_init()` initializes the four input pins with pull-ups and latches their state at startup.
The schematic switches connect the GPIO to GND when ON, so the API reports ON as bit 1:

- GP19 / DIPSW0 -> bit0
- GP18 / DIPSW1 -> bit1
- GP17 / DIPSW2 -> bit2
- GP16 / DIPSW3 -> bit3

`dipsw_get_startup_state()` returns the latched startup setting; `dipsw_read()` samples the live switch state.
The controller currently prints the startup value as `DIPSW startup state: 0xN` for verification.

## SLOT#1 ROM mode

The low two startup DIPSW bits are sent to the CPU FPGA with SPI command `19h` before MSX reset is released:

| DIPSW[1:0] | Mode | SLOT#1 behavior |
| --- | --- | --- |
| `00` | Physical cartridge | Physical `/SLTSL1`, `/CS1`, `/CS2`, `/CS12` are enabled normally |
| `01` | ASCII8K | Physical SLOT#1 is disabled; ROM1 maps four 8KB windows |
| `10` | Physical cartridge | DIPSW[0]=0 disables the ROM1 mapper regardless of DIPSW[1] |
| `11` | ASCII16K | Physical SLOT#1 is disabled; ROM1 maps two 16KB windows |

ASCII8K bank registers are written in the mirrored ranges `6000h-67FFh`, `6800h-6FFFh`, `7000h-77FFh`, `7800h-7FFFh` and map CPU windows `4000h-5FFFh`, `6000h-7FFFh`, `8000h-9FFFh`, `A000h-BFFFh` respectively.
ASCII16K bank registers use `6000h-67FFh` for `4000h-7FFFh` and `7000h-77FFh` for `8000h-BFFFh`. All banks reset to segment zero; R-Type's special initial bank is not implemented.
Bank writes are captured by the FPGA and never assert ROM1 CE. Reads assert ROM1 CE only for the selected mapper windows. Pico ROM1 Direct Flash operations keep their separate 20-bit physical address path.

`fpga_set_slot1_rom_mode()` sends command `19h` and waits for FPGA acknowledgement. Pico-local key 3 programs ROM1 from `/bios/extrom.rom`; the startup DIPSW setting selects how the CPU reads that image. No file-selection browser is provided.

