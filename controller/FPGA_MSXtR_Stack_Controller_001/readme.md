# 環境設定
	環境変数 PICO_SDK_PATH に、https://github.com/raspberrypi/pico-sdk を clone したパスを指定しておく。
	WSLでやるなら、 WSL側の環境変数に WSL側のパスで記入すること。

	cd {SDKパス}
	git clone https://github.com/raspberrypi/pico-sdk
	setx PICO_SDK_PATH={SDKパス}

# ビルド
	cmake --build build --target fpga_msxtr_controller
	cmake -S . -B build -DPICO_BOARD=pico2_w

## RAMダンプ

MSX CPU動作中にMENUキーでPicoへバス所有権を移し、8キーでC000h～DFFFhの8192byteと、E600h～E6FFhの256byteを標準出力へダンプする。先頭にCPUのPCとスロット情報を出力し、メモリは16byte/行のアドレス付き16進数で表示する。

現在のスロットマッピングを維持し、RAMへの書き込み、リセット、CPUへのバス所有権の自動復帰は行わない。CPU動作中の8キーでは実行しない。ダンプ終了後、MENUキーでCPUへ戻す。

DFFFhの色変数とRAM常駐コードに加え、E62Dh・E63Fh・E651hを先頭とする3レコードの判定用データも採取する。WSLでのファームウェアビルド確認済み。実機読出し確認は未実施。

## CPU切替のSP観測

3キーのデバッグ表示に `SP capture: Z80@0488=0xXXXX R800@04BF=0xXXXX` を追加した。
Z80所有かつPC=0488hの間は保存時SP、R800所有かつPC=04BFhの間は復元時SPを毎クロック更新し、
それ以外は保持する。コアSPの観測だけを行い、追加のメモリ読出し・書込みは発行しない。

9キーで両ラッチを5A5Ahへ初期化する。CPU/Picoのどちらが所有していても実行でき、
成功時に `SP capture cleared to 5A5A.`、通知待ち失敗時にtimeoutを表示する。
起動処理中にも記録されるため、調査対象のCPU切替の前に9キーを押す。
値は対象PCへ来るたび更新されるので、複数回の切替を挟まず、切替ごとに3キーで確認する。
5A5Ahは初期化の目印であり、専用の記録有効フラグではない。

SPI0Ahの応答長は既存の33byteのまま。診断32byteのbyte16-17にZ80保存SP、byte18-19にR800復元SPを
little-endianで配置する。SPI14hはクリア専用で、応答データなし・SPI_INTRで完了通知する。
旧イベント記録器は接続しない。FPGAとPicoの両方を更新する。SPI速度70MHzとbyte間待ち1usは維持。

2026-10-05: test_006で実BIOS切替後のEFE8h/EFE8h、SPI表示、リセット/クリアの5A5Ah、
メモリ要求なしを確認。PicoビルドとVDPログSPI回帰もPASS。
同一設定のPnRでsetup/hold違反0件、最悪setup slack +0.020ns (追加前+0.029ns)。
SSRAM RTL、CPU実行制御、SDCは未変更。実機の起動と観測値は未確認。

## 漢字SerialROM更新 (2026-10-08)

FPGA/Picoの両方を更新する。W25Q32JVSSの先頭256KB (00000h-3FFFFh) だけを使用し、残りの領域は消去・書き込みしない。

MENUでPicoへ所有権を移し、SDカードに正確に262144byteの `/bios/kanji.rom` を置く。

- 7キー: 漢字SerialROMだけを消去・更新・全256KB照合する。ROM0/ROM1は変更しない。
- 4キー: 既存のROM0 BIOS更新に続けて漢字SerialROMを更新・照合する。漢字イメージをROM1へ書く旧処理は廃止。
- 5キー: ROM0/ROM1とSerialROM先頭256byteをダンプする。
- 更新成功後はMENUでCPUへ戻す。失敗時はPico所有を維持し、未照合のままCPUへ戻す操作を拒否する。

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

