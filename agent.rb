
TMPD_S = "#{TMP_ROOT}/session-#{FSID}"

SAgentParams = "#{TMPD_S}/ssh-agent-params"
FileUtils.mkdir_p TMPD_S


Dir.glob "#{TMP_ROOT}/session-*" do |sd|
    start_clk, sid = sd.split(".")
    # start_clk != (IO.read(/proc/ sid /stat).split[21] rescue nil)
    if start_clk != (IO.read("/proc/#{sid}/stat").split[21] rescue nil)
        Process.kill(File.read("#{sd}/ssh-agent-params/ssh_agent_pid").to_i) rescue next
        File.delete(File.read("#{sd}/ssh-agent-params/ssh_auth_sock")) rescue next
        FileUtils.rm_rf sd
    end
end


def getFing idf
    IO.popen [*%W{ssh-keygen -lf}, idf] do |io|
        return io.read.strip.sub(/\s*#.*$/, "").split[1]
    end
end


def displaySSHAgentParams
    getKeyListInSSHAgent
    STDOUT.puts "SSH_AUTH_SOCK=#{ENV['SSH_AUTH_SOCK']}; export SSH_AUTH_SOCK;"
    STDOUT.puts "SSH_AGENT_PID=#{ENV['SSH_AGENT_PID']}; export SSH_AGENT_PID;"
    STDOUT.puts "echo Agent pid #{ENV['SSH_AGENT_PID']};"
end

def destroySSHAgent
    clearKeysInSSHAgent
    ssh_agent_pid = File.read("#{SAgentParams}/ssh_agent_pid").strip rescue nil
    if ssh_agent_pid
        Process.kill :TERM, ssh_agent_pid.to_i rescue nil
    end
    ssh_auth_sock = File.read("#{SAgentParams}/ssh_auth_sock").strip rescue nil
    if ssh_auth_sock && File.exist?(ssh_auth_sock)
        File.delete(ssh_auth_sock) rescue nil
    end
    FileUtils.rm_rf SAgentParams
end


def set_ssh_agent_params retry_item
    if ENV['SSH_AUTH_SOCK']
        return nil
    end
    ssh_auth_sock = nil
    ssh_agent_pid = nil
    if retry_item == :previous && File.exist?("#{SAgentParams}/ssh_auth_sock") && File.exist?("#{SAgentParams}/ssh_agent_pid")
        ssh_auth_sock = File.read("#{SAgentParams}/ssh_auth_sock").strip
        ssh_agent_pid = File.read("#{SAgentParams}/ssh_agent_pid").strip
        retry_item = :new
    else
        r, w = IO.pipe

        pid = Process.spawn(
          "/usr/bin/ssh-agent -s -a #{TMPD_S}/ssh-agent-sock",
          out: w, # 標準出力をパイプにリダイレクト
          err: w, # 標準エラーをパイプにリダイレクト
          close_others: true # 必要なファイルディスクリプタ以外を閉じる
        )
        
        w.close # 書き込み側を閉じる
        
        r.each_line do |line|
          if line =~ /SSH_AUTH_SOCK=(.*?)(;|$)/
            ssh_auth_sock = $1
          end
          if line =~ /SSH_AGENT_PID=(.*?)(;|$)/
            ssh_agent_pid = $1
          end
        end
        
        r.close # 読み取り側を閉じる
        
        Process.wait(pid) # 子プロセスの終了を待つ


        if !ssh_auth_sock || !ssh_agent_pid
            userPrompt :msg, "ERROR: cannot start ssh-agent."
            exit 1
        end
        FileUtils.mkdir_p SAgentParams
        STDERR.puts "ssh-agent started with PID #{ssh_agent_pid}, SOCK #{ssh_auth_sock}" if ENV["DEBUG"]
        File.write("#{SAgentParams}/ssh_auth_sock", ssh_auth_sock)
        File.write("#{SAgentParams}/ssh_agent_pid", ssh_agent_pid)
        retry_item = nil
    end
    ENV['SSH_AUTH_SOCK'] = ssh_auth_sock
    ENV['SSH_AGENT_PID'] = ssh_agent_pid
    if ENV["FOR_EVAL"]
        fd = ENV["FOR_EVAL"].to_i
        begin
            IO.new(fd, "w") do |io|
                io.puts "export SSH_AUTH_SOCK='#{ssh_auth_sock}';"
                io.puts "export SSH_AGENT_PID='#{ssh_agent_pid}';"
                io.puts "echo Agent pid #{ssh_agent_pid};"
            end
        rescue
        end
    end
    retry_item
end

def getKeyListInSSHAgent
    keylist = []
    retry_item = :previous
    begin
        IO.popen ["/usr/bin/ssh-add", "-l"], err: [:child, :out] do |io|
            io.each_line do |line|
                case line
                when /Could not open a connection to your authentication agent/
                    raise Err.new(line)
                when /Error connecting to agent: No such file or directory/
                    raise Err.new(line)
                end
                keylist.push line.strip.split[1]
            end
        end
    rescue Err => e
        if retry_item.nil?
            userPrompt :msg, "ERROR: Cannot start ssh-agent (#{e.message})."
            exit 1
        end
        retry_item = set_ssh_agent_params retry_item
        retry
    end
    keylist
end

def clearKeysInSSHAgent
    keyList = getKeyListInSSHAgent
    system("#{SSH_ADD} -D") if !keyList.empty?
end
                

def ssh_add idf, phrase
    idf_mod = false
    if BY_VSCODE
        w = `cmd.exe /c "echo %USERPROFILE%" 2>/dev/null < /dev/null`.chomp
        idOnWinHome = `wslpath '#{w}'`.chomp + "/tmpid"
        system "cp -f #{idf} #{idOnWinHome}"
        idf = "#{w}/tmpid"
        idf_mod = true
    end
    begin
        #x = [*SSH_ADD, idf].shelljoin
        x = ["ssh-add.exe", idf].shelljoin
        #PTY.spawn ["sh", "-c", "SSH_ASKPASS= " + x].join(" ") do |r, w, pid|
        PTY.spawn "SSH_ASKPASS= #{SSH_ADD_PTY.shelljoin} ${idf}" do |r, w, pid|
            begin
                loop do
                    r.sync = true
                    ra, = select [r]
                    buff = r.readpartial(1024) #rescue break
                    case buff
                    when /Enter passphrase for .*:/
                        w.write phrase + "\r\n"
                        w.flush
                    when /Bad passphrase/
                        Process.kill :TERM, pid
                        userPrompt :msg, "ERROR: passphrase required for #{idf}\nPlease add it with ssh-add #{idf}, before running #{Prog}"
                        exit 1
                    when /Identity added: /
                        Process.wait(pid)
                        return true
                    end
                end
            ensure
                Process.wait(pid) rescue Errno::ECHILD
            end
        end
    ensure
        FileUtils.rm_f idf if idf_mod
    end
    return false
end



