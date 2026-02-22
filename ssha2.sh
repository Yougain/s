require temp_path


eval $(ssh-agent -a "$(temp_path ssh_agent_socket)" -s) 2>/dev/null >/dev/null

END << 'EOF'
    /usr/bin/ssh-agent -k >/dev/null 2>&1 || true
EOF

scp() {
    "`which scp`" -S /usr/local/bin/ssha2 "$@"
}

ssh(){
    /usr/local/bin/ssha2 "$@"
}

__ssha2_ssh_add(){
    /usr/local/bin/ssha2 --ssh-add "$@"
}

__ssha2_ssh_agent(){
    /usr/local/bin/ssha2 --ssh-agent "$@"
}

# コマンド名そ  のままで呼べるように
alias ssh-add='__ssha2_ssh_add'
alias ssh-agent='__ssha2_ssh_agent'

export GIT_SSH=/usr/local/bin/ssha2
