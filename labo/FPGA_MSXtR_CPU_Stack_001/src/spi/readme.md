# FPGA → Pico
spi_intr = L にする。
FPGA は、Pico側がそれを認知して、それに対応するアクションを起こすまで、出したい内容を FIFO に蓄えておきます。
FPGA は、受信時に mosi で 1byte を受け取るとともに、miso で 64h (1byte) を返します。
FPGA存在確認は、その 64h によって、存在して通信可能であることを通知します。
通信相手であるマイコンは、64h を受け取ったら、存在していると認識します。
spi_cs_n = H にすると、通信途中であっても、中断して初期状態に戻ります。

# Pico → FPGA
spi_cs_n = L にして、次の 1byte を送ります。
- 01h ... FPGA I/O 書込み要求
- 02h ... FPGA I/O 読み出し要求
- 03h ... FPGA Memory 書込み要求
- 04h ... FPGA Memory 読み出し要求
- 05h ... FPGA BUSY check
- 06h ... MSX Hardware reset ON
- 07h ... MSX Hardware reset OFF
- 08h ... MSX Hardware pause ON
- 09h ... MSX Hardware pause OFF
- 0Ah ... Debug
- 0Bh ... MSX BootROM enable
- 0Ch ... MSX BootROM disable
- FFh ... FPGA 存在確認

# FPGA I/O 書き込み要求
FPGAが出したいと思っている内容を受け取る要求です。
つまり、FPGAに送信権を与えるコマンドです。

|順番|値|内容|
|---|---|---|
|#1|01h|FPGA受信要求|
|#2|アドレス番号|書き込み対象となるFPGA内のI/Oアドレス番号|
|#3|データ|指定のI/Oアドレスに書き込むデータ|

# FPGA I/O 読み出し要求
FPGAに対して、Picoから制御を要求するコマンドです。

|順番|値|内容|
|---|---|---|
|#1|02h|FPGA送信要求|
|#2|アドレス番号|書き込み対象となるFPGA内のI/Oアドレス番号|
|-|待機|応答を返せるタイミングで SPI_INTR=1 にする|
|#3|データ|指定のI/Oアドレスから読み込んだデータ（FPGAから出力)|

# FPGA Memory 書き込み要求
FPGAが出したいと思っている内容を受け取る要求です。
つまり、FPGAに送信権を与えるコマンドです。

|順番|値|内容|
|---|---|---|
|#1|03h|FPGA Memory 書き込み要求|
|#2|アドレス番号(下位8bit)|書き込み対象となるFPGA内のMemoryアドレス番号|
|#3|アドレス番号(上位8bit)|書き込み対象となるFPGA内のMemoryアドレス番号|
|#4|データ|指定のMemoryアドレスに書き込むデータ|

# FPGA Memory 読み出し要求
FPGAに対して、Picoから制御を要求するコマンドです。

|順番|値|内容|
|---|---|---|
|#1|04h|FPGA Memory 読み出し要求|
|#2|アドレス番号(下位8bit)|書き込み対象となるFPGA内のMemoryアドレス番号|
|#3|アドレス番号(上位8bit)|書き込み対象となるFPGA内のMemoryアドレス番号|
|-|待機|応答を返せるタイミングで SPI_INTR=1 にする|
|#4|データ|指定のMemoryアドレスから読み込んだデータ（FPGAから出力)|

# FPGA BUSY check
FPGAがBUSY状態かどうかを確認する要求です。

|順番|値|内容|
|---|---|---|
|#1|05h|FPGA BUSY check|
|#2|応答|FPGAがBUSY状態の場合は、01hを返す。BUSY状態でない場合は、00hを返す。(FPGAから出力)|

# MSX Hardware reset ON
PicoからFPGAに対して、MSXのハードウェアリセットを要求するコマンドです。

|順番|値|内容|
|---|---|---|
|#1|06h|MSX Hardware reset ON|

# MSX Hardware reset OFF
PicoからFPGAに対して、MSXのハードウェアリセットを解除するコマンドです。

|順番|値|内容|
|---|---|---|
|#1|07h|MSX Hardware reset OFF|

# MSX Hardware pause ON
PicoからFPGAに対して、MSXのハードウェアポーズを要求するコマンドです。

|順番|値|内容|
|---|---|---|
|#1|08h|MSX Hardware pause ON|

# MSX Hardware pause OFF
PicoからFPGAに対して、MSXのハードウェアポーズを解除するコマンドです。

|順番|値|内容|
|---|---|---|
|#1|09h|MSX Hardware pause OFF|

# FPGA 存在確認
FPGAが存在するかどうかを確認する要求です。

|順番|値|内容|
|---|---|---|
|#1|FFh|FPGA 存在確認|
