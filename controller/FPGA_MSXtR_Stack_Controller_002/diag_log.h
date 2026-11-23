#ifndef DIAG_LOG_H
#define DIAG_LOG_H

// 起動タイミングを変えずに診断ログを残すためのリングバッファ。
// diag_log() はどちらのコアからでも呼べる。USB 端末が接続されるまで保持し、
// diag_log_flush() で端末へ出力する。
// 通常は無効。有効にするには cmake に -DDIAG_LOG_ENABLE=1 を指定して再構成する。

#ifndef DIAG_LOG_ENABLE
#define DIAG_LOG_ENABLE 0
#endif

#if DIAG_LOG_ENABLE
void diag_log_init( void );
void diag_log( const char *format, ... );
void diag_log_flush( void );
#else
#define diag_log_init()		((void)0)
#define diag_log( ... )		((void)0)
#define diag_log_flush()	((void)0)
#endif

#endif /* DIAG_LOG_H */
