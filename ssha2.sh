

# 共通ランナー: 子に FOR_EVAL(FD) を渡し、親で全文を eval・子の終了コードを返す
__run_with_eval() {
    local cmd=$1; shift
    set -euo pipefail

    coproc { :; }
    local rfd=${COPROC[0]}
    local wfd=${COPROC[1]}

    (
        export FOR_EVAL=$wfd
        exec "$(command -v "$cmd")" "$@"
    ) &
    local child_pid=$!

    # 親側の書き込みFDは閉じる（EOF検出のため）
    exec {wfd}>&-

    # 子からの全文を読み取り、eval
    local payload
    payload=$(<&"$rfd")
    [ -n "$payload" ] && eval "$payload"

    # 後片付け
    exec {rfd}<&-

    # set -e だと wait の非ゼロ終了で落ちるため一時的に無効化
    set +e
    wait "$child_pid"
    local rc=$?
    set -e
    return "$rc"
}

# ラッパー関数
ssh()        { __run_with_eval ssh "$@"; }
__ssh_add()    { __run_with_eval ssh-add "$@"; }
__ssh_agent()  { __run_with_eval ssh-agent "$@"; }

# コマンド名そのままで呼べるように
alias ssh-add='__ssh_add'
alias ssh-agent='__ssh_agent'
