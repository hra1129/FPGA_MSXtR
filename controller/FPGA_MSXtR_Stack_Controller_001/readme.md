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

