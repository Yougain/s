#!/bin/bash


CODE="`which code`"
if [ -n "$CODE" ] && grep "Microsoft Corporation." "$CODE" 2> /dev/null ; then
    exec code "$@"
fi


launch(){
    if [ -z "$SSH_VSCODE_PORT" ]; then
        echo "Error: SSH_VSCODE_PORT is not set. Cannot connect to remote VSCode launcher in WSL." >&2
        exit 1
    fi
	SOCK2="$SOCK"
	c2="$c"
    echo "open remote $(hostname -s)" | nc localhost $SSH_VSCODE_PORT > /dev/null
    (( i=0 ))
    while [ "$SOCK2" == "$SOCK" ]; do
        SOCK2=$(ls -t `find /run/user/$UID /mnt/wslg/runtime-dir -name "vscode-ipc-*.sock" 2>/dev/null` | head -1)
        sleep 0.3
        (( i++ ))
        if [ $i -gt 50 ]; then
            echo "Error: Timeout waiting for new VSCode socket" >&2
            exit 1
        fi
    done
    SOCK="$SOCK2"

	echo executing VSCODE_IPC_HOOK_CLI="$SOCK" $c "$@" ... >&2
	c="$(ls -t `find ~/.vscode-server -name code`|head -1)"
    if ! VSCODE_IPC_HOOK_CLI="$SOCK" $c "$@";then
        echo "Error: Failed to launch VSCode." >&2
        exit 1
    fi
	echo OK
}


SOCK=$(ls -t `find /run/user/$UID /mnt/wslg/runtime-dir -name "vscode-ipc-*.sock" 2>/dev/null` | head -1)

if [ -z "$SOCK" ]; then
    echo "VSCode socket not found.
Trying launch VSCode ..." >&2
	launch "$@"
fi
c="$(ls -t `find ~/.vscode-server -name code`|head -1)"
res="` VSCODE_IPC_HOOK_CLI="$SOCK" $c "$@" 2>&1 | head -2`"
if [ -n "$res" ] ;then
    echo "$res" >&2
	echo "Trying launch VSCode ..." >&2
	launch "$@"
fi

