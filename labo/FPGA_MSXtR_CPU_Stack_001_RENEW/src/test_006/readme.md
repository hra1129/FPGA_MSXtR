# test_006: BIOS CPU Switch

test_005のトップ接続、4個のSSRAMモデル、SPI起動手順、実行スクリプトを基にしたCPU切替専用テスト。FPGA_MSXtR_CPU_Stackの構造とタイミング制約は変更しない。CPU状態やRAMのforce、実BIOS全体の起動は行わない。検出した切替要求の再受理問題については、後述のs2026_cpu_select修正を適用した設計で検証する。

## 実行

このフォルダのrun.batを実行する。ModelSimのvlib/vlog/vsimがPATHに必要。
全階層波形をtest_006.wlf、シミュレーションログをlog.txtへ保存する。成功時のみ終了コード0。異常・10msタイムアウトは終了コード1。
続けてCPU/Pico要求のHigh保持・同じ切替先への指定・Low後の再受付を単体検査し、selector_request.wlfとselector_request.logへ保存する。

## 検証用FlashROM

controller/bios_image_tool/msxtr.romをバイナリで読み、0180h～0185hの入口と046Ah～04E8hの切替本体・照会処理・制御値テーブルを元のアドレスへコピーする。原本ROMは書き換えず、tb.sv内の仮想FlashROMへ配置する。BIOSのレイアウトが想定と異なる場合は停止する。A=0とA=2の有効な指定を対象とし、不正な引数の経路は検証しない。

起動コードはDI、A8h=F0h (page0/1=SLOT#0-0、page2/3=SLOT#3-0)、SP設定、FCB1h初期化だけに絞る。二次スロットはリセット値00hを利用する。FlashROMのデータ確定と出力有効化は70ns、出力解除は20nsでモデル化する。

準備段階でZ80から制御レジスタへのOUTによりR800を起動し、R800自身がA=0でCALL 0180hを実行する。その結果R800は04B9hで停止する。これは初期待機状態を作る段階であり、BASIC起動処理を再現するものではない。

## 保存・復元ケース

1. Z80から開始し、A=2 (R800指定)とA=0 (Z80指定)を交互にCALL 0180hへ渡し、CPU種を10回切り替える。毎回、呼び出し前に既知のレジスタ値を設定する。
2. 各回の戻り先は1100h、1200h、...、1A00h。phase=0～9でCPU種と戻り先を照合する。
3. 10回目の後はZ80でA=0を再指定し、同CPU呼び出しとして1B00hへ戻る (phase=10)。実際のCPU種の変化が10回ちょうどであることを検査し、余計な切替も検出する。

全11回の復帰で主・裏BC/DE/HL、IX/IY、AF/AF'、I、SPと戻り先PCを照合する。BC=1234h、DE=5678h、HL=9ABCh、BC'=2345h、DE'=6789h、HL'=ABCDh、IX=3456h、IY=789Ah、AF'=A744h、I=5Ah、SP=F000hを使用する。AFは指定値に応じて0244hまたは0044h。交互切替数はtb.svのc_switch_count=10で設定する。

BIOS自身のPUSH/EXX/EX AF/LD (FFFDh),SP/OTIR/LD SP,(FFFDh)/POP/RETを実行する。初期化時はDI、外部INTは常時非アサート。BIOS末尾のEIはそのまま実行する。割り込みの注入、Rレジスタ値、BASICの式評価は対象外。

切替時には全run_ack=0、SSRAM内部busy解除、全SRAM CS非選択を検査する。[SWITCH]に両CPUのPC、[RESTORE]に復元中のPC/SP/AF、[RETURN]と[REGISTERS]に戻り先と復元値を出力する。SRAMモデルの取引ログと全階層波形で、FFFDh/FFFEhやスタック読み書きも追跡できる。

## 結果

2026-10-04: 交互CPU切替10回と同CPU指定1回がすべてPASS、シミュレーション時刻約2.3604174msで終了 (コード0)。準備後のR800停止PCは04B9h、Z80からの切替でZ80停止PCは04B7hとなり、実機の停止位置と一致した。全11回の主・裏レジスタ、IX/IY、AF/AF'、I、SP、RET先はすべて一致し、余分なCPU種の変化や未完了SRAM取引は検出しなかった。初期の3ケース版もPASSしていた。

この条件では実機の初回Syntax Errorは再現しない。実BASICの呼び出し状態、割り込み動作、実デバイスの遅延・電気特性まで検証した結果ではない。合成・PnR・実機書き込みは行っていない。

### 2026-10-05 SP観測の検証

コアSPをtopへ観測用に出力し、Z80所有/PC=0488hとR800所有/PC=04BFhの間だけ
それぞれ16bitラッチへ取り込む構成を検査する。PC一致期間は毎クロック更新し、その後保持する。
BIOSの保存・復元後、両ラッチがEFE8hとなることを確認した (呼出し前SP=F000h、CALLで2byte、
保存レジスタで22byte使用)。このテスト値を実BASICの期待SPとして扱わない。

SPI0Ahから既存33byteを読み、byte16-19が両ラッチをlittle-endianで返し、末尾A5hが変わらないこと、
読出しで記録が変わらないことを検査する。SPI14hが一度だけクリア信号を出し、
両ラッチを5A5Ahへ戻し、MCUメモリバス要求を出さないことも検査する。MSXリセット時も5A5Ahへ戻す。
10回の切替、同CPU呼出し、全レジスタ復元および要求多重受付防止の既存検査もPASS。

SP観測版のGowin合成/PnRはsetup/hold違反0件、最悪setup slack +0.020ns。
SSRAM RTLとタイミング制約は変更していない。実機検証は未実施。

### `+cache_sp_reuse`: FFFDh stack-line再取得

初期化のR800→Z80切替を実行した後、次の3回のBIOS呼出しを行う専用ケース。

1. Z80の呼出し前SPをF06Chにし、BIOSのCALL/保存push後にFFFDhへF054hが保存される状態でR800へ切替。
2. R800からZ80へ戻し、Z80側SPをF090hにして、次のCALL/保存push後にFFFDhへF078hを保存してR800へ切替。
3. 2回目のR800復元後、SP=F090hで戻ることを確認。

起動準備後のowner変化が Z80→R800→Z80→R800 となる。TBはpage3=segment0の物理SSRAMにある
03FFDh/03FFEhが、各復元前に54h/F0h、次に78h/F0hへ更新されたことを直接確認する。
同時にR800のcache missが両方で物理ライン03FF8hのburst readを発行した回数を数え、
2回となることを確認する。R800復元地点SPもF054h、F078hの順で照合する。

実行方法 (通常の`run.bat`でコンパイルしたworkライブラリを使用):

```bat
vsim -c -t 1ps -l cache_sp_reuse.log -wlf cache_sp_reuse.wlf tb +cache_sp_reuse -do run.do
```

2026-10-05: PASS。物理SSRAMのFFFDh/FFFEh書込み、2回の同一stack line burst refill、
R800 SP復元F054h→F078h、3回の復帰と4回のCPU所有者遷移を確認。
これはRTL/SSRAMモデル上でvalid invalidationと再fillが動くことを示すが、
実機の54h再現原因や実SerialSRAMの電気的タイミングを確定する結果ではない。

## 切替要求の重複受付防止

修正前は切替完了でセレクタがIDLEへ戻った次のクロックに、要求元がまだHighの切替要求を下げるのと同時に同じ要求を再受理していた。CPU種は変わらないがrun_reqが再低下し、余計な停止・再開が発生する。CPU種の変化数だけでは検出できない。

s2026_cpu_selectにCPU/Picoそれぞれの受理済みFFを追加し、同じHigh期間の要求は一度だけ受け付ける。要求がLowになると再受付可能に戻す。全run_ack停止待ちと、切替完了後の選択先再開は従来どおり。CPUコアとタイミング制約は変更しない。

test_006はCPU/Picoの要求立上り数と、それぞれの停止処理への入口数を照合する。修正後はCPU要求19回・停止処理19回、Pico要求1回・停止処理1回となり、全11回のBIOS復帰とレジスタ検査がPASS (終了コード0)。OTIRが複数の制御値を送るため、正当な要求数はCPU種の変化10回とは異なる。

tb_selector_requestでは、切替完了後も要求を12クロックHighで保持し、再停止しないことを直接検査する。CPU/Picoとも同じ切替先への指定と、Low後の次要求もPASS。修正後のtest_006.wlfには余分な停止・再開が含まれない。実機Syntax Errorとの因果関係と、修正後の実機動作は未確認。
