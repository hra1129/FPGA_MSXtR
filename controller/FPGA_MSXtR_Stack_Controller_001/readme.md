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

