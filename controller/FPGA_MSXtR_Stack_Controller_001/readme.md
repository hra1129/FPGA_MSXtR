# 環境設定
	環境変数 PICO_SDK_PATH に、https://github.com/raspberrypi/pico-sdk を clone したパスを指定しておく。
	WSLでやるなら、 WSL側の環境変数に WSL側のパスで記入すること。

	cd {SDKパス}
	git clone https://github.com/raspberrypi/pico-sdk
	setx PICO_SDK_PATH={SDKパス}

# ビルド
	cmake --build build --target fpga_msxtr_controller
	cmake -S . -B build -DPICO_BOARD=pico2_w
