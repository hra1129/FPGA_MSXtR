# Copilot Instructions

## このプロジェクトの概要
- MSXコンピューターをFPGAで再現するプロジェクトです。
- 主にVerilog/SystemVerilogでハードウェアの設計を行い、C/C++でソフトウェアの開発を行います。
- ２つのFPGA(TangNano20K)と、２つのマイコン（RasberryPiPico2W, STM32）を使用します。
- 目標は、MSXのハードウェアを忠実に再現し、オリジナルのMSXソフトウェアが動作することです。
- さらに、MSXの拡張機能や新しい機能も追加していく予定です。
- キーボードは、STM32 を使用して MSXキーマトリクスに変換して I2C で RaspberryPiPico2W に送信します。
- RaspberryPiPico2W は、キーボードの情報や SDカードのデータを SPI で FPGA に送信します。

## このプロジェクトのコーディングスタイル
### Verilog, SystemVerilog
- インデントはタブ記号を使う
- タブインデントはスペース4つ分である
- begin は行末に書く
- end の前は改行する
- else の前は改行する
- 1行に複数の文を書くことは避ける
- 変数名・関数名・タスク名・モジュール名は小文字で、単語の区切りはアンダースコアを使う（例: my_variable）
- if の次の ( はスペースを詰める。

例: 
  if( condition ) begin
    // code
  end
  else begin
    // code
  end

- モジュールはフォルダに分けて管理し、そのテストはそのフォルダ内に test_xxx のフォルダを作成して配置する
- シミュレーションは ModelSim Starter Edition (vlog, vsim) を使用する。パスは通っている。

### C, C++
- インデントはタブ記号を使う
- タブインデントはスペース4つ分である
- { は行末に書く
- } の前は改行する
- else の前は改行する
- 1行に複数の文を書くことは避ける
- 変数名・関数名・クラス名・モジュール名は小文字で、単語の区切りはアンダースコアを使う（例: my_variable）

例: 
  if( condition ) {
    // code
  }
  else {
    // code
  }

## フォルダ構成
- controller: RaspberryPiPico2W のコード
- keyboard: STM32 のコード
- fpga: FPGA のコード
- labo: 開発用のコードやドキュメントなど
- doc: ドキュメントや設計資料など
- pcb: KiCad の基板設計データ

controller フォルダの中には、Pico のファームウェアコードを格納するフォルダが並び、
各フォルダの中の build フォルダをカレントにして、WSL から make -j すればビルドできるようにしてある。

# コマンドの実行
vsim, vlog, vlib などの ModelSIM コマンドや、それを実行するだけのバッチファイルの実行に関しては、承認確認は必要なく、即実行して構いません。