# disk_if: FPGA_MSXtR のディスクエミュレーター I/F 仕様

- 版: 0.3 (FPGA 側と Pico ファームを実装済み。実機での確認はこれから)
- 対象ハードウェア: FPGA_MSXtR_CPU_Stack2_000 (FPGA) と FPGA_MSXtR_Stack_Controller_002 (Raspberry Pi Pico 2W)
- 読み手: MSX-DOS2 のディスクドライバー (DSKIO / DSKCHG など) を書く AI エージェント (Muse くん)
- 用語: MUST = 必須、SHOULD = 推奨、MAY = 任意

この文書は、次の 2 部構成です。

| 部 | 内容 | Muse くん |
|---|---|---|
| 第 1 部 (§1〜§9) | MSX から見たレジスタ、手順、エラー、注意点 | **必読。ドライバーはこの部分だけで書ける** |
| 第 2 部 (§10〜§12) | FPGA と Pico の内部 (SPI コマンド、Pico の動作) | 参考。読まなくてよい |

---

# 第 1 部 MSX 側から見た仕様

## 1. 概要

- tR の FDC (TC8566AF) は存在しない。FDC のレジスタを触るドライバーは動かない。
- その代わりに、DOS ROM と同じスロットに **セクター単位のブロックデバイス I/F (disk_if)** がある。
- MSX が 1 セクター (512 バイト) の読み出しか書き込みを要求すると、FPGA が Pico に伝え、Pico が SD カードを読み書きして結果を返す。
- MSX から見ると「コマンドを書く → BUSY が落ちるまでポーリング → 512 バイトを転送する」だけの単純なデバイス。
- FDC 特有の処理 (シーク、モーター、トラックやサイドの計算、ステップレート、DMA) は**要らない**。セクター番号は論理セクター番号 (LBA) で渡す。
- 割り込みは使わない (disk_if は INT を出さない)。

### 1.1 ドライブの中身 (Pico 側のモードで決まる。MSX からは区別しなくてよい)

| Pico のモード | ドライブの中身 | セクター範囲 | ファイルシステム |
|---|---|---|---|
| DSK イメージモード | SD カード上の `/DSK/2DD.DSK` (720KB の 2DD イメージ) | 0〜1439 | FAT12 (2DD、メディア ID F9h) |
| SD 直接モード | SD カード全体 (セクター 0 = SD の物理セクター 0) | 0〜SD の容量 | FAT12 または FAT16。それ以外 (FAT32 など) のときはドライブが Not ready になる |

- モードは Pico 側のキー操作で切り替わる。切り替えたときは「ディスク交換」として MSX に見える (§6)。
- SD 直接モードでは、セクター 0 がパーティションテーブル (MBR) のこともある。**MBR の解釈 (パーティションの開始 LBA への変換) はドライバー側でやる (MUST)**。disk_if は受け取ったセクター番号をそのまま SD に渡す。
- 範囲外のセクターを指定したときは、エラー 8 (Record not found) が返る。
- ドライブは当面 1 台 (DRIVE=0) だけ。DRIVE が 0 以外のときは、エラー 2 (Not ready) が返る。

## 2. 前提条件 (アドレスとスロット)

- disk_if のレジスタは、**スロット 3-2 のページ 1 の 7FF1h〜7FFBh** にある (メモリ空間。I/O ポートではない)。
- スロット 3-2 のページ 1 には DOS ROM (16KB × 4 バンク) がある。レジスタは ROM に重ねて置かれており、この範囲の ROM の内容は読めない。
- レジスタは **DOS ROM のどのバンクを選んでいても同じように見える**。
- ROM 側の制約:
  - 7FF1h〜7FFBh の 11 バイトに置いたコードやデータは読めない (MUST: 使わない)。
  - 7FF0h は書き込み専用のバンクレジスタ。読むと ROM の内容が返る。7FFCh〜7FFFh は ROM のまま。
- 7FF0h に書き込むと DOS ROM のバンクが切り替わる (bit1〜0 = バンク 0〜3)。7FF0h はこれまでどおりで、disk_if とは関係ない。
- disk_if は MSX リセットで初期化される (§4 の初期値)。

## 3. レジスタマップ

| アドレス | 読み出し | 書き込み | 備考 |
|---|---|---|---|
| 7FF0h | (ROM) | BANK | 既存。DOS ROM のバンク |
| 7FF1h | 予約 (FFh) | 無視 | 既存の挙動を残す。使わない |
| 7FF2h | STATUS | CMD | §4、§5 |
| 7FF3h | DRIVE | DRIVE | ドライブ番号。当面は 0 だけ |
| 7FF4h | MEDIA | MEDIA | メディア ID (DSKIO の C レジスタの値)。Pico は参考に使うだけ |
| 7FF5h | SECTOR bit7〜0 | SECTOR bit7〜0 | 論理セクター番号 (32bit、リトルエンディアン) |
| 7FF6h | SECTOR bit15〜8 | SECTOR bit15〜8 | |
| 7FF7h | SECTOR bit23〜16 | SECTOR bit23〜16 | |
| 7FF8h | SECTOR bit31〜24 | SECTOR bit31〜24 | |
| 7FF9h | DATA | DATA | 512 バイトバッファへの窓。アクセスするたびにポインタが 1 進む (§7) |
| 7FFAh | ERRCODE | 無視 | 最後に完了したコマンドのエラーコード (§8) |
| 7FFBh | IFVER (01h) | 無視 | I/F の版。この版では 01h |

- **BUSY=1 の間は、DRIVE、MEDIA、SECTOR、DATA への書き込みを無視する。** CMD への書き込みも ABORT 以外は無視する。
- BUSY=1 の間に DATA を読むと FFh が返り、ポインタは進まない。
- DRIVE、MEDIA、SECTOR は書いた値を読み返せる。コマンドを実行しても値は変わらない (続けて次のセクターを読むときは SECTOR だけ書き換えればよい)。
- I/F の有無は、7FFBh が 01h かどうかで判定できる (SHOULD)。FFh などそれ以外なら、この I/F はないものとする。

## 4. STATUS (7FF2h 読み出し)

| bit | 名前 | 意味 | 変化するとき |
|---|---|---|---|
| 7 | BUSY | 1 = コマンド処理中 (バッファの持ち主は Pico)。0 = 待機中 (バッファの持ち主は MSX) | READ/WRITE を書くと 1。Pico が完了するか ABORT で 0 |
| 6 | ERROR | 1 = 最後に完了したコマンドがエラーで終わった。ERRCODE が有効 | 完了時に更新する。READ/WRITE を書くと 0 |
| 5 | CHANGED | 1 = 前回クリアしてからディスクが交換された | Pico がディスクを交換すると 1。CMD=CLRCHG で 0。**MSX リセット直後は 1** |
| 4 | READY | 1 = ディスクが入っていて使える | Pico が設定する |
| 3 | WPROT | 1 = 書き込み禁止 | Pico が設定する |
| 2〜0 | - | 予約 (0) | |

- 初期値 (MSX リセット直後): BUSY=0、ERROR=0、CHANGED=1。READY と WPROT は、Pico が設定した値が MSX リセットをまたいで残る。
- READY=0 でも READ/WRITE は受け付ける (Pico が Not ready で完了させる)。ただし Pico が止まっているとタイムアウトまで待つことになる。そのため、**READ/WRITE の前に READY を見て、0 ならすぐにエラー 2 (Not ready) を返す (SHOULD)**。
- WPROT=1 のときに WRITE しても、エラー 0 (Write protected) で完了する。WRITE の前に WPROT を見て、すぐにエラー 0 を返してもよい (MAY)。

## 5. CMD (7FF2h 書き込み)

| 値 | 名前 | 動作 | BUSY |
|---|---|---|---|
| 00h | RSTPTR | DATA のポインタを 0 に戻すだけ | 変わらない |
| 01h | READ | DRIVE/SECTOR の 1 セクターを読む。完了するとバッファに 512 バイトが入る | 1 になる |
| 02h | WRITE | バッファの 512 バイトを DRIVE/SECTOR に書く | 1 になる |
| 10h | CLRCHG | CHANGED を 0 にする | 変わらない |
| 80h | ABORT | 処理中のコマンドを打ち切る。BUSY=0、ERROR=1、ERRCODE=2 (Not ready) になる。BUSY=0 のときは何もしない | 0 になる |
| 上記以外 | - | 無視 (将来の予約) | - |

- BUSY=0 のときは、CMD にどの値を書いても (無視される値も含めて) DATA のポインタが 0 に戻る。
- BUSY=1 の間に受け付けるのは ABORT だけ。ABORT を受け付けたときもポインタは 0 に戻る。それ以外の値は無視され、ポインタも変わらない。
- ABORT のあとに Pico から遅れて届いた結果は、FPGA が捨てる (要求の通し番号で照合する)。そのため、ABORT の直後に次のコマンドを出してよい。

## 6. ディスク交換 (DSKCHG 用)

- CHANGED=1 のとき: 「交換された」を返す (B=FFh)。そのあと CMD=CLRCHG で CHANGED を 0 にする (MUST)。
- CHANGED=0 のとき: 「交換されていない」を返してよい (B=01h)。disk_if は交換を確実に検知できるので、「不明」(B=00h) を返す必要はない。
- CHANGED が 1 になるのは、Pico のモード切り替え、ディスクイメージの交換 (将来)、SD カードの抜き差しのとき。
- 交換されたときは、メディア ID も変わることがある (DSK モードの F9h と、SD 直接モードの F8h など)。DPB はブートセクターから作り直す (MUST)。

## 7. DATA バッファ (7FF9h)

- 512 バイトのバッファへの窓。内部のポインタは 9bit (0〜511)。読み書きのたびに 1 進み、511 の次は 0 に戻る。
- ポインタは次のときに 0 に戻る: CMD への書き込み (§5)、コマンドの完了 (BUSY が 1 から 0 になったとき)、MSX リセット。
- そのため、ドライバーは次の手順で使う。
  - READ: CMD=READ → BUSY=0 になるのを待つ → ポインタは 0 になっているので、7FF9h を 512 回読む。
  - WRITE: CMD=RSTPTR → 7FF9h に 512 回書く → CMD=WRITE (CMD を書くとポインタは 0 に戻るが、バッファの中身はそのまま残る)。
- **BUSY=0 の間、バッファの持ち主は MSX。** バッファの中身は、次の READ が完了するまでそのまま残る。
- **LDIR / LDDR は使えない** (転送元のアドレスが 7FF9h に固定されているため)。`LD A,(HL)` / `LD (DE),A` / `INC DE` のループか、それを展開したもので転送する。
- 512 バイトより多く読み書きしてもよいが、ポインタが 0 に戻って先頭からの繰り返しになる。

## 8. エラーコード (ERRCODE、7FFAh)

ERRCODE の値は、**DSKIO が A レジスタで返すエラーコードそのまま**なので、ドライバーは変換せずに返してよい。

| ERRCODE | 意味 | 起きる場面 |
|---|---|---|
| 0 | Write protected | WPROT=1 のディスクに書こうとした |
| 2 | Not ready | ディスクが入っていない、FAT12/16 以外、DRIVE が範囲外、ABORT した |
| 4 | Data (CRC) error | ERR ファイルの指定 |
| 6 | Seek error | ERR ファイルの指定 |
| 8 | Record not found | 範囲外のセクター、または ERR ファイルの指定 |
| 10 | Write fault | SD への書き込みに失敗した、または ERR ファイルの指定 |
| 12 | Other error | その他、または ERR ファイルの指定 |

- **エラーかどうかは STATUS の ERROR ビットで判断する (MUST)。** ERRCODE=0 は Write protected の意味でも使うので、ERRCODE だけでは成功か失敗かを判断できない。
- **READ がエラーで終わっても、バッファにはデータが入っている。** ERR ファイルでエラーにしたセクターでも、DSK イメージの内容が入っている。コピープロテクトの再現などのため、ドライバーはデータを転送先へコピーしてからエラーを返す (SHOULD)。
- WRITE がエラーで終わったときは、SD には書かれていない。

## 9. 手順 (ドライバーの書き方)

### 9.1 DSKIO の流れ

1. 7FFBh が 01h であることを確かめる。初期化時に 1 回だけでよい。
2. STATUS を読む。READY=0 なら、エラー 2 で返す。WRITE のときに WPROT=1 なら、エラー 0 で返してよい。
3. 1 セクターずつ次を繰り返す。
   - READ: DRIVE/MEDIA/SECTOR を書く → CMD=01h → 完了を待つ → 512 バイトを転送先へコピーする → ERROR=1 なら ERRCODE を返して終わる。
   - WRITE: CMD=00h → 転送元から 512 バイトを DATA に書く → DRIVE/MEDIA/SECTOR を書く → CMD=02h → 完了を待つ → ERROR=1 なら ERRCODE を返して終わる。
4. 戻り値 (Cy、A、B = 処理できなかった残りのセクター数) は、DSKIO の規約どおりに設定する。

### 9.2 完了待ちとタイムアウト

- BUSY=0 になるまで STATUS をポーリングする。
- Pico の処理時間の目安は、DSK モードで 1 セクター数 ms〜数十 ms。SD カードによっては、書き込みが 250ms 程度かかることがある。
- **タイムアウトは R800 でも 2 秒以上になるようにする (MUST)。** 目安は 3 秒程度。ループ回数で数える場合は、R800 は Z80 よりずっと速いので、R800 を基準に回数を決める。
- タイムアウトしたら、CMD=80h (ABORT) を書いて、エラー 2 (Not ready) を返す。
- 割り込みは禁止しても許可してもよい。disk_if は割り込みに依存しない。

### 9.3 転送先がページ 1 のとき

- レジスタはスロット 3-2 のページ 1 にあるので、DATA を読み書きしている間は、ページ 1 がスロット 3-2 になっていなければならない。
- そのため、DSKIO の転送先 (または転送元) がページ 1 (4000h〜7FFFh) にかかるときは、**ページ 3 などのバッファを経由する (MUST)**。FDC 用の DOS ドライバーでよく使われる方法と同じ。

### 9.4 Z80 アセンブリの例 (参考)

```asm
DIF_STATUS	equ	07FF2h	; R: STATUS / W: CMD
DIF_CMD		equ	07FF2h
DIF_DRIVE	equ	07FF3h
DIF_MEDIA	equ	07FF4h
DIF_SECTOR	equ	07FF5h	; 4 バイト、リトルエンディアン
DIF_DATA	equ	07FF9h
DIF_ERRCODE	equ	07FFAh
DIF_IFVER	equ	07FFBh

CMD_RSTPTR	equ	000h
CMD_READ	equ	001h
CMD_WRITE	equ	002h
CMD_CLRCHG	equ	010h
CMD_ABORT	equ	080h

ST_BUSY		equ	7
ST_ERROR	equ	6
ST_CHANGED	equ	5
ST_READY	equ	4
ST_WPROT	equ	3

; ---------------------------------------------------------------
; 1 セクター読み出し
;   入力: DE = 転送先 (ページ 1 以外), SECTOR/DRIVE/MEDIA は書き込み済み
;   出力: Cy=0 成功 / Cy=1 エラー (A = DSKIO エラーコード)
;   転送先にはエラーのときもデータが入る
; ---------------------------------------------------------------
dif_read_sector:
	ld	a, CMD_READ
	ld	(DIF_CMD), a
	call	dif_wait		; Cy=1 ならタイムアウト (A=2)
	ret	c
	push	af			; A = STATUS (Cy=0) を保存
	ld	hl, DIF_DATA
	ld	b, 0			; 256 回 × 2 バイト = 512 バイト
.loop:
	ld	a, (hl)
	ld	(de), a
	inc	de
	ld	a, (hl)
	ld	(de), a
	inc	de
	djnz	.loop
	pop	af
	bit	ST_ERROR, a
	ret	z			; 成功。Cy=0 (bit 命令は Cy を変えない)
	ld	a, (DIF_ERRCODE)
	scf
	ret

; ---------------------------------------------------------------
; 1 セクター書き込み
;   入力: HL = 転送元 (ページ 1 以外), SECTOR/DRIVE/MEDIA は書き込み済み
;   出力: Cy=0 成功 / Cy=1 エラー (A = DSKIO エラーコード)
; ---------------------------------------------------------------
dif_write_sector:
	ld	a, CMD_RSTPTR
	ld	(DIF_CMD), a
	ld	de, DIF_DATA
	ld	b, 0
.loop:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	ld	a, (hl)
	ld	(de), a
	inc	hl
	djnz	.loop
	ld	a, CMD_WRITE
	ld	(DIF_CMD), a
	call	dif_wait
	ret	c
	bit	ST_ERROR, a
	ret	z
	ld	a, (DIF_ERRCODE)
	scf
	ret

; ---------------------------------------------------------------
; BUSY=0 まで待つ
;   出力: Cy=0, A = STATUS / Cy=1, A = 2 (タイムアウト。ABORT 済み)
;   ループ回数は仮の値。R800 で 2 秒以上になるよう実測して調整すること
; ---------------------------------------------------------------
dif_wait:
	ld	c, 30			; 外側のループ (仮)
.outer:
	ld	hl, 0			; 内側 65536 回
.inner:
	ld	a, (DIF_STATUS)
	bit	ST_BUSY, a
	jr	z, .done
	dec	hl
	ld	a, h
	or	l
	jr	nz, .inner
	dec	c
	jr	nz, .outer
	ld	a, CMD_ABORT
	ld	(DIF_CMD), a
	ld	a, 2			; Not ready
	scf
	ret
.done:
	or	a			; Cy=0 (A=STATUS は変わらない)
	ret
```

- 上の例は手順を示すためのもの。レジスタの退避、DSKIO の戻り値、ページ 1 のバッファ経由は、ドライバー側で整えること。

### 9.5 DSKCHG の例 (参考)

```asm
dif_dskchg:
	ld	a, (DIF_STATUS)
	bit	ST_READY, a
	jr	z, .not_ready
	bit	ST_CHANGED, a
	ld	b, 1			; 交換されていない
	jr	z, .ok
	ld	a, CMD_CLRCHG
	ld	(DIF_CMD), a
	ld	b, 0FFh			; 交換された (DPB を作り直す)
.ok:
	or	a
	ret
.not_ready:
	ld	a, 2
	scf
	ret
```

---

# 第 2 部 FPGA と Pico の内部仕様 (参考)

## 10. FPGA (disk_if モジュール)

- `src/dos_mapper/dos_mapper.v` の中の fdc8566 を disk_if (`src/disk_if/disk_if.v`) に置き換えた。アドレスデコード (address_decode.v の dos_mapper_cs) と、ROM の CE マスク (msx_slot.v の 3FF1h〜3FFBh) はそのまま使う。
- 512 バイトのバッファはシングルポート RAM。BUSY=0 の間は MSX 側 (ポインタ)、BUSY=1 の間は SPI 側がアドレスを使う。MSX バスの読み出しデータは 1clk 遅れて `bus_rdata_en` と一緒に返せばよいので (memory_mapper と同じ方式)、DATA は RAM の同期読み出しでそのまま応答する。
- 要求の通し番号 SEQ (8bit): READ/WRITE を受け付けるたびに 1 増やす。MSX リセットでは初期化しない。Pico の 21h、22h、23h は SEQ が一致して、かつ BUSY=1 のときだけ受け付ける。
- READY と WPROT は、FPGA の電源投入時のリセットでのみ 0 に初期化する (MSX リセットでは消えない)。CHANGED は MSX リセットで 1 にする。
- Pico と FPGA が同じサイクルに 23h の受理と MSX の ABORT を受けた場合は、23h の完了を優先する (Pico に返す 00h と FPGA の状態が食い違わないようにするため)。
- `fdc_interrupt` は廃止した (INT には何もつながない)。
- テスト: `src/disk_if/test_001` (dos_mapper + ip_spi の結合テスト、`run.bat`)。

## 11. SPI コマンド (Pico → FPGA、追加分)

既存の SPI プロトコル (`src/spi/readme.md`) に次を追加する。どれもバスの所有権は取らない (CPU は止まらない)。
- 20h〜23h の FPGA→Pico のバイトは、既存の 12h と同じように、1 バイトごとに `spi_intr=H` を待ってから読む。
- Pico→FPGA のバイト (SEQ、結果、22h のデータ) は、既存の 16h と同じように `spi_write_blocking` のあと `sleep_us(1)` を挟んで送る (intr は待たない)。
- 24h は、受信が終わると `spi_intr=H` になる (19h と同じ)。

### 11.1 ディスク要求ありの通知

- 05h (BUSY check) の応答の bit3 = DISK_REQ (= disk_if の BUSY)。
- 11h (キーマトリクス更新) の最初の応答バイトの bit4 = DISK_REQ。
- Pico は 2ms ループでこのビットを見て、1 なら 20h から処理を始める。

### 11.2 20h: 要求内容の読み出し

| 順番 | 方向 | 内容 |
|---|---|---|
| #1 | Pico→FPGA | 20h |
| #2 | FPGA→Pico | STATUS (§4 と同じ) |
| #3 | FPGA→Pico | SEQ |
| #4 | FPGA→Pico | CMD (01h=READ / 02h=WRITE) |
| #5 | FPGA→Pico | DRIVE |
| #6 | FPGA→Pico | MEDIA |
| #7〜#10 | FPGA→Pico | SECTOR (下位バイトから) |

### 11.3 21h: バッファの読み出し (MSX の WRITE 要求のとき)

| 順番 | 方向 | 内容 |
|---|---|---|
| #1 | Pico→FPGA | 21h |
| #2 | Pico→FPGA | SEQ |
| #3 | FPGA→Pico | 00h = 受け付けた / 01h = 拒否した (SEQ が違う、または BUSY=0)。拒否なら Pico は CSn を H にする |
| #4〜#515 | FPGA→Pico | バッファの 512 バイト (先頭から) |

### 11.4 22h: バッファへの書き込み (MSX の READ 要求のとき)

| 順番 | 方向 | 内容 |
|---|---|---|
| #1 | Pico→FPGA | 22h |
| #2 | Pico→FPGA | SEQ |
| #3 | FPGA→Pico | 00h = 受け付けた / 01h = 拒否した |
| #4〜#515 | Pico→FPGA | バッファに書く 512 バイト (先頭から) |

### 11.5 23h: 完了通知

| 順番 | 方向 | 内容 |
|---|---|---|
| #1 | Pico→FPGA | 23h |
| #2 | Pico→FPGA | SEQ |
| #3 | Pico→FPGA | 結果。bit7 = ERROR、bit6〜0 = ERRCODE |
| #4 | FPGA→Pico | 00h = 受け付けた (BUSY=0、ポインタ=0 にした) / 01h = 拒否した (ABORT 済みなど) |

### 11.6 24h: メディア状態の設定

| 順番 | 方向 | 内容 |
|---|---|---|
| #1 | Pico→FPGA | 24h |
| #2 | Pico→FPGA | bit0 = READY、bit1 = WPROT、bit7 = 1 なら CHANGED を 1 にする |

- いつでも受け付ける。

## 12. Pico の動作

- **起動:** SD のマウントとモードの初期化が終わってから 24h で READY/WPROT を設定し、そのあとで MSX のリセットを解除する (DOS が起動したときに、すでに READY になっているようにする)。SD がなければ READY=0 にする。
- **要求の処理:** DISK_REQ=1 なら、20h で内容を読む → READ なら SD から読んで 22h → WRITE なら 21h で受け取って SD に書く → 23h で完了を通知する。
- **DSK イメージモード:**
  - `/DSK/2DD.DSK` を開いたままにして、`f_lseek(sector × 512)` → `f_read` / `f_write` + `f_sync` (pico-sdk 同梱の FatFs は `FF_USE_FASTSEEK=0` なので fast seek は使わない。720KB ならクラスタチェーンが短いので十分速い)。
  - ファイルが読み取り専用属性なら WPROT=1 にする。
  - `/DSK/2DD.ERR` (1 セクター 1 バイト) は、マウント時に RAM へ読み込む。ファイルがなければ、全セクター 0 (エラーなし) とする。
  - ERR の値が 0 以外のセクターの場合:
    - READ: データを返したうえで、ERROR=1、ERRCODE=その値にする。
    - WRITE: 書かずに、ERROR=1、ERRCODE=その値にする。
  - セクター番号がイメージの範囲外なら、エラー 8 にする。
- **SD 直接モード:**
  - FatFs をアンマウントし、`disk_read` / `disk_write` で SD のセクターを直接読み書きする。
  - モードに入るときに MBR / ブートセクターを見て、FAT12/16 でなければ READY=0 にする。
- **書き込み禁止:** 将来の SET ファイルの `protect` で WPROT=1 にする。当面の `/DSK/2DD.DSK` は書き込みを許可する (読み取り専用属性のときだけ WPROT=1)。
- **モード切り替え:** Pico のローカルメニューの D キーで切り替える。DISK_REQ=0 のときだけ切り替え、切り替えたら 24h (CHANGED=1) を送る。
- **SD アクセスは 1 つのコアにまとめる** (FatFs はスレッドセーフではない)。Core 0 に集約し、SD のマウントも Core 0 の起動処理で行う。
- 実装: `controller/FPGA_MSXtR_Stack_Controller_002/disk_emu.c` (fpga_io.c の `fpga_disk_*` が 20h〜24h)。

---

## 変更履歴

| 版 | 日付 | 内容 |
|---|---|---|
| 0.1 | 2026-11-26 | 初版ドラフト |
| 0.2 | 2026-11-26 | FPGA 側を実装。§5 の CMD 書き込み時のポインタの扱いを明確化 (BUSY=0 ならどの値でも 0、BUSY=1 なら ABORT のときだけ 0)。§10 を実装に合わせて修正 (先読みレジスタではなく同期読み出し)。§11 に spi_intr の扱いを追記。MSX から見た動作の変更は §5 の書き方の明確化のみ |
| 0.3 | 2026-11-26 | Pico ファームを実装。§12 を実装に合わせて修正 (fast seek は使わない、読み取り専用属性なら WPROT=1、D キーでモード切り替え、SD アクセスは Core 0)。MSX から見た動作の変更はなし |
