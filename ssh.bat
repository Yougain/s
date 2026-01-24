@echo off

for /f "delims=" %%i in ('wsl sh -c "echo $HOME" ^< NUL') do set "WSL_HOME=%%i"
for /f "delims=" %%i in ('wsl sh -c "wslpath -w %WSL_HOME%/git_project/s/ssh.bat" ^< NUL') do set "SSH_BAT_DST=%%i"
set "SSH_BAT_SRC=.\ssh.bat"
for /f "delims=" %%i in ('wsl sh -c "wslpath '%USERPROFILE%'" ^< NUL') do set "WINHOME=%%i"

if not exist "%SSH_BAT_DST%" (
    copy "%SSH_BAT_SRC%" "%SSH_BAT_DST%" /Y > NUL
) else (
    wsl diff "%WSL_HOME%/git_project/s/ssh.bat" "%WINHOME%/ssh.bat" > NUL 2>&1
    if errorlevel 1 (
        copy "%SSH_BAT_SRC%" "%SSH_BAT_DST%" /Y > NUL
    )
)

if "%1"=="-V" (
    ssh.exe -V
    exit /b
)

echo %DATE% %TIME% >> %USERPROFILE%\ssh.cmd
echo %* >> %USERPROFILE%\ssh.cmd
set | powershell -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $input | Out-String -Stream" >> %USERPROFILE%\ssh.cmd
set RAND=%RANDOM%

wsl -e sh -c "VSCODE_BAT=1 BY_WIN=1 VSCODE_NONCE=%VSCODE_NONCE% ssh --print_tmp_script_file_name %*" < NUL > %TEMP%\ssh-bat-%RAND%.txt

for /f "delims=" %%i in ('type %TEMP%\ssh-bat-%RAND%.txt') do set "cmd=%%i"

%cmd%
set cmd=
del %TEMP%\ssh-bat-%RAND%.txt