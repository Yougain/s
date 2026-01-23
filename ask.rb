# ruby lib

def _get_controlling_tty
  pid = Process.pid
  
  while pid > 1
    # Use ps to get the TTY for the process
    stdout, stderr, status = Open3.capture3("ps -o tty= -p #{pid}")
    if status.success?
      tty = stdout.strip
      if tty != '?' && !tty.empty?
        # Format the TTY path appropriately
        if tty.start_with?('pts/') || tty.start_with?('tty')
          return "/dev/#{tty}"
        else
          # For macOS or other formats like ttysXXX
          return "/dev/#{tty}"
        end
      end
    end
    
    # Get the parent PID
    stdout, stderr, status = Open3.capture3("ps -o ppid= -p #{pid}")
    if status.success?
      ppid = stdout.strip.to_i
      pid = ppid
    else
      break
    end
  end
  
  nil  # No TTY found
end

Ctty = _get_controlling_tty


def setupIO
    if STDIN.tty?
        cin = STDIN
    else
        Ctty && (cin = File.open(Ctty, 'r+') rescue nil)
    end
    if STDERR.tty?
        cout = STDERR
    else
        Ctty && (cout = cin || (File.open(Ctty, 'r+') rescue nil))
    end
    [cin, cout]
end

Cin, Cout = setupIO


def prompt_pw msg
    Cout.print msg
    Cout.flush
    begin
        Cout.echo = false
        password = Cin.gets.chomp
    ensure
        Cout.echo = true
        Cout.puts ""
    end
    return password
end

def prompt_input msg
    Cout.print msg
    Cout.flush
    input = Cin.gets.chomp
    return input
end

def prompt_yn msg
    loop do
        Cout.print msg
        Cout.flush
        res = Cin.gets.chomp
        if res =~ /yes|y|no|n/
            return res =~ /y/
        end
    end
end

def put_msg msg
    Cout.print msg
    Cout.flush
end


def userPrompt mode, msg = nil
    #p mode
    case mode
    when :yn
        if Cin && !BY_VSCODE
            return prompt_yn
        elsif IN_WSL || BY_VSCODE
            return system "winInputBox --confirm Empty passphrase. Are you sure?"
        end
    when :msg
        if Cin && !BY_VSCODE
            return put_msg msg
        elsif IN_WSL
            return system "winInputBox --message #{msg.chomp}"
        end
    when :passwd, :passwd, :input
        if Cin && !BY_VSCODE
            if mode == :passwd || mode == :passwd
                input = prompt_pw msg
            else
                input = prompt_input msg
            end
        elsif BY_VSCODE
            input = `get_win_passwd`.chomp
        elsif IN_WSL
            input = `winInputBox #{msg.chomp}`.chomp
        end
        return input
    end
end


