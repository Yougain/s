#!/bin/bash
# 同一セッション下で /dev/tty から読み込み待機中のプロセスを検出

# 現在のセッションIDを取得
current_sid=$(ps -o sid= -p $$)

echo "現在のセッションID: $current_sid"
echo "---"

# 同じセッション内の全プロセスを検索
for pid in $(ps -o pid= -o sid= | awk -v sid="$current_sid" '$2 == sid {print $1}'); do
    # プロセスが存在しない場合はスキップ
    [ ! -d "/proc/$pid" ] && continue
    
    # プロセスのファイルディスクリプタを確認
    tty_fd=""
    for fd in /proc/$pid/fd/*; do
        [ -e "$fd" ] || continue
        target=$(readlink "$fd" 2>/dev/null)
        if [[ "$target" == "/dev/tty" ]]; then
            tty_fd=$(basename "$fd")
            break
        fi
    done
    
    # /dev/tty を開いていない場合はスキップ
    [ -z "$tty_fd" ] && continue
    
    # プロセスの状態を確認
    if [ -r "/proc/$pid/status" ]; then
        state=$(grep "^State:" /proc/$pid/status | awk '{print $2}')
        wchan=$(cat /proc/$pid/wchan 2>/dev/null)
        
        # システムコールの状態を確認
        syscall_info=""
        syscall_name=""
        if [ -r "/proc/$pid/syscall" ]; then
            syscall_info=$(cat /proc/$pid/syscall 2>/dev/null)
            # システムコール番号を取得（最初のフィールド）
            syscall_num=$(echo "$syscall_info" | awk '{print $1}')
            
            # 主要なシステムコール番号（x86_64）
            # 0: read, 1: write, 7: poll, 23: select, 232: epoll_wait, 等
            case "$syscall_num" in
                0) syscall_name="read" ;;
                1) syscall_name="write" ;;
                7) syscall_name="poll" ;;
                23) syscall_name="select" ;;
                232) syscall_name="epoll_wait" ;;
                257) syscall_name="openat" ;;
                *) syscall_name="syscall_$syscall_num" ;;
            esac
        fi
        
        # スリープ状態（読み込み待機の可能性）
        if [[ "$state" == "S" ]] || [[ "$state" == "D" ]]; then
            # wchan で read 系の待機を確認、またはシステムコールが read の場合
            if [[ "$wchan" =~ (read|wait|tty|n_tty) ]] || [[ "$syscall_name" == "read" ]]; then
                cmdline=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
                [ -z "$cmdline" ] && cmdline="<no cmdline>"
                
                echo "PID: $pid"
                echo "  コマンド: $cmdline"
                echo "  状態: $state"
                echo "  待機: $wchan"
                echo "  FD: $tty_fd -> /dev/tty"
                
                # システムコール情報を表示
                if [ -n "$syscall_info" ]; then
                    echo "  システムコール: $syscall_name ($syscall_info)"
                fi
                
                # 追加情報: スタックを確認（読み込み中か判定）
                if [ -r "/proc/$pid/stack" ]; then
                    stack=$(grep -E "tty|read" /proc/$pid/stack 2>/dev/null | head -n 1)
                    [ -n "$stack" ] && echo "  スタック: $stack"
                fi
                echo "---"
            fi
        fi
    fi
done

echo "検出完了"
