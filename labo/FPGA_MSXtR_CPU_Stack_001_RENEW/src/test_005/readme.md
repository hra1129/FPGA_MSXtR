# test_005: Z80 Cartridge Slot Signals

CPU Stackトップを実際のZ80コアで動かす短縮テスト。実機BIOS、内部TEST_BOOTROM、CPUバスのforceは使用しない。RTL本体は変更しない。

## 実行

このディレクトリで `run.bat` を実行する。ModelSimのvlib/vlog/vsimがPATHに必要。
全階層を `test_005.wlf` に保存し、ログは `log.txt` に保存する。
コンパイルエラー、安全性違反、ROMプログラムの失敗、カバレッジ不足、10msのタイムアウトは終了コード1。
全条件を通過した場合だけPASSメッセージと終了コード0を返す。

競合検出の負例は、run.batによるコンパイル後に次で実行する。終了コード1が期待値。

```bat
vsim -c -t 1ps -l contention.log -wlf contention.wlf tb +inject_contention -do run.do
```

## ROMと起動手順

ROMデータはtb.sv内の配列に生成する。実機用イメージの書き換えは行わない。

- FlashROM0: DI、A8h=C0h、SP=FF00h、A8h=E4h、JP 1000h。
- 最終マップ: page0=SLOT#0-0、page1=SLOT#1、page2=SLOT#2、page3=SLOT#3-0。
- Secondary Slotはリセット値0を利用。SerialSRAMモデル4個を使用し、初期化を待ってからSPIでCPUへ所有権を渡しリセットを解除する。RAM探索は行わない。
- SLOT#0-0 FlashROM: 1000hから共通検査コードを実行。1100hのC7hを読み、1200hへ5Ahの書き込み信号を出す (ROM内容は変更しない)。
- SLOT#1: 4000hから実行。4100hのA6hを読む。4200hへ5Ahを書く。
- SLOT#2: 8000hから実行。8100hの39hを読む。8200hへ5Ahを書く。
- 4領域とも共通の生成処理でデータ比較、IN A,(A8h)とE4h比較、OUT (98h),A、ADD HL,BC、PUSH HL、POP DEを実行。データ参照アドレス、期待値、次のジャンプ先だけ領域に合わせる。
- FlashROMからSLOT#1、SLOT#2の順に実行した後、FlashROM0の0080hへ戻る。HL=2000h、DE=C100h、BC=0101hを設定し、Z80自身のLDIRでSRAM用コードと検査データをコピーする。SRAMモデルへの直接ロードやforceは使用しない。
- SLOT#3-0 SerialSRAM: C100hからコピーしたコードを実行。C200hの57hを読み、C300hへ5Ahを書く。スタックFF00hとは分離する。
- 最後はFlashROM0の0040hへ戻る。F3hへA5hを書くと正常完了、比較失敗は0030hへJPしてF3hへ5Ahを書く。
- 書き込みは検査用ROMのコードを変更せず、モデル側で宛先・値を検査する。メガROMのバンク切替はまだモデル化していない。

## 観察と合否

FlashROM、SLOT#1、SLOT#2、SLOT#3-0の各実行区間でM1 read、通常memory read、memory write、I/O read、I/O write、非アクセス内部サイクル、refreshの7項目が観測されることを検査する。
M1/read/writeは対象エッジの件数、I/O read/internal/refreshは該当状態を観測したクロック数を表示する。
PUSH/POPによるSLOT#3-0アクセスも波形に含む。最終SP=FF00hとマップE4hを検査するが、POP DEのデータ内容までは合否判定していない。

- CPU側slot_dとCartridge側cartridge_dを別のtriバスとして構成し、DIRと/OEに従い双方向バッファを模擬する。
- FlashROM0はCPU側に接続。カートリッジROMはCartridge側に接続する。プルアップはweak駆動。
- カートリッジROMはデータ確定80ns、出力解除20nsの仮定を使用し、遅延後の駆動enableを競合監視する。
- 複数の能動ドライバは値が同じでも競合として検出する。信号変化イベントとクロックの両方で監視。
- /RDと/WRの重複、CPUデータ駆動中のRead方向、I/O Read中のRead方向、書き込み中のアドレス・データ変化、CPU読み出し取り込み点のX/Z・外部データ未駆動を検査する。
- ROM1は未使用であり、選択された場合は失敗する。

レベルシフタ自体の伝搬遅延やアナログ特性、基板故障はモデル化していない。モデルのPASSだけで実機の電気的安全性を保証するものではない。

## 2026-10-03 検証結果

修正前のRTLでは約467us、PC=400Fhにて次を検出しFAIL (終了コード1):

```text
I/O read direction violates board workaround:
PC=400f address=05aa8 bus_io=0 bus_write=0 cpu_oe=0
```

/IORQと/RDがともにLowのまま、内部bus_ioが0となりDIRがCartridge→CPUへ戻る区間。
`msx_slot.v` の外部メモリread判定へ `slot_iorq_n` を追加し、物理I/Oサイクル終了までCPU→Cartridge方向を維持する修正を実施。
修正後は約547usでPASS (終了コード0)。/IORQがLowの全期間で方向を検査し、両スロットでM1=15、通常read=1、memory write=1、I/O read観測=29クロック、I/O write=1、内部サイクル観測=84クロック、refresh観測=315クロックを確認した。
`+inject_contention` はROM0読み出しに別ドライバを重ね、PC=0000hでCPU側競合を検出して終了コード1となることを確認。

### FlashROM・SerialSRAM実行の追加

4領域の拡張版もPASS、終了コード0。約2.30msで完了し、各区間で上記と同じ7項目のカバレッジを確認した。
`[EXEC]` ログには開始時刻を表示する (timescaleによりps表示): FlashROM=448.664us、SLOT#1=495.038us、SLOT#2=541.411us、SerialSRAM=2249.977us。
全区間とLDIRコピー時の波形を同じtest_005.wlfに保存する。

### Read方向の終了後保持

アドレスだけではなく/MREQ LowをRead方向の条件とし、外部メモリRead判定を42MHzのFFへ記録する。現在の判定と遅延判定のORで、開始は即時、終了は1クロック (約23.3ns) 遅延する。
I/O、書き込み、CPUデータ出力、Flash直接アクセス、内部スロット選択時はCPU→Cartridge方向を優先する。
/MREQまたは/IORQ終了後、残ったI/OアドレスだけでRead方向へ戻る動作は抑止される。

test_005でROM出力解除20nsを待つことと、次クロックでDIRがHighへ戻ることを直接検査。70回の解除検査がすべて通過し、4領域の全カバレッジと競合検査もPASS (終了コード0)。
msx_slot/test_001も76 PASS / 0 FAIL。既存の未接続ポート警告3件あり。合成・PnRと実機での確認は未実施。

### リフレッシュ中のROM CE抑止

`msx_slot.v` のROM選択代入全経路で/RFSHを判定し、Lowをサンプリングしたクロックでは両ROM CEのFFへHighを設定する。Flash直接アクセスと漢字ROM選択も対象。通常のROM0 CE出力はSLOT_CSと同じ `/MREQ OR 選択FF` とし、要求のない期間にリフレッシュアドレスをデコードしてもCEが出ないようにする。ただしPicoの `w_flash_en = 1` ではROM0 CEを選択FF直結とし、/MREQ Highのままでも直接アクセスできる。単体テストでこの例外を検査し、94 PASS / 0 FAIL。ROM1はFlash直接アクセス時に/MREQ、漢字ROMアクセス時に/IORQで同様に限定する。/RFSHによる出力段の組合せマスクは行わない。内部cpu_flash_csはバス要求前にも必要なアドレス分類なので、端子CEではなく選択FFから判定する。
test_005は/RFSH開始時のFF応答1クロックを考慮して両CE非選択を検査し、CEまたは/MREQの変化時にも要求外ROM0 CEを検査する。4領域の全項目と方向解除検査70回がPASS (終了コード0)。

### リフレッシュアドレスの保持

`cz80_inst.v` はT3のcount 2でコアのリフレッシュアドレスをラッチし、直ちにアドレスバスへ切り替える。/RFSHの立下りはcount 2からcount 4へ2クロック遅らせ、スロット側のアドレスFF更新後にLowとする。T4のcount 11での立上りは変更せず、それまでラッチ値を保持する。
cz80/test_002で開始タイミングとLow期間のアドレス保持76回を確認し、既存の読み書き検査もPASS。test_005では今回のプログラムのI=0、ページ0のMAIN-ROMマッピングを前提に、Low開始時からslot_aがラッチ値と一致することを検査。4領域それぞれ285回のリフレッシュ観測と全既存検査がPASS (終了コード0)。タイミング制約は変更していない。合成・PnRと実機での確認は未実施。
msx_slot/test_001では要求中の両ROMのクロック間CE保持、次クロックでの抑止、内部Flash分類抑止、/RFSH解除時の古い選択値の非露出、次クロックでの復帰を確認。加えて要求外CE抑止、/MREQ・/IORQと同時のCE解除、リフレッシュ前後の余分なROM0 CE抑止を確認。94 PASS / 0 FAIL。合成・PnRと実機での確認は未実施。

