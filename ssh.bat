@echo off

if "%1"=="-V" (
    ssh.exe -V
    exit /b
)

echo %DATE% %TIME% >> c:\Users\Yougain\ssh.cmd
echo %* >> c:\Users\Yougain\ssh.cmd
set | powershell -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $input | Out-String -Stream" >> c:\Users\Yougain\ssh.cmd
wsl -e sh -c "SSH_BAT=1 VSCODE_NONCE=%VSCODE_NONCE% ssh %*"