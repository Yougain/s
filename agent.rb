
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
end


require 'socket'
require 'find'
require 'fileutils'

def cleanup_dead_ssh_agent_sockets
  my_uid = Process.uid
  collected_sockets = []

  # 1. /tmp 配下を走査してパス名に "ssh" と "agent" を含むソケットを収集
  %W{/tmp #{ENV['HOME']}/.ssha #{ENV['HOME']}/.local/tmp}.each do |d|
		if File.readable?(d)
		  Find.find d do |path|
		    # 他ユーザーのアクセス権のないディレクトリ等を安全にスキップ
		    st = File.lstat(path) rescue next

		    # 自分の所有するソケットファイルかチェック
		    if st.socket? && st.uid == my_uid
		      if path.include?("ssh") && path.include?("agent")
		        collected_sockets << path
		      end
		    end
		  end
		end
	end

  # 2. 各ソケットに対して接続テストを行い、開いていない（死んでいる）ものを削除
  deleted = []
  collected_sockets.each do |sock_path|
    is_alive = false
    begin
      # 実際にソケット接続を試みる
      UNIXSocket.open(sock_path) do |s|
        is_alive = true
      end
    rescue Errno::ECONNREFUSED, Errno::ENOENT, Errno::ENOTSOCK
      # 接続拒否（相手プロセスがいない）、または既に存在しない場合は死んでいると判定
      is_alive = false
    rescue Errno::EACCES, Errno::EPERM
      # 権限エラー等の場合は安全のため削除しない
      is_alive = true
    rescue => e
      is_alive = false
    end

    unless is_alive
      begin
        File.unlink(sock_path)
        deleted << sock_path
        
        # もし親ディレクトリが /tmp/ssh-XXXXXX のような空ディレクトリなら一緒に削除
        parent_dir = File.dirname(sock_path)
        if parent_dir =~ %r{\A/tmp/ssh-[^/]+\z} && (Dir.entries(parent_dir) - %w[. ..]).empty?
          Dir.rmdir(parent_dir) rescue nil
        end
      rescue => e
        # 削除失敗時は無視
      end
    end
  end

  deleted
end


cleanup_dead_ssh_agent_sockets

# 実行例:
# deleted_sockets = cleanup_dead_ssh_agent_sockets
# puts "Deleted dead sockets: #{deleted_sockets.inspect}"

SSHAgent = Struct.new :pid, :sock, :cmdline


class NewAgent
	@@created = nil
	def initialize arg = nil
		if arg
			p
			r, w = IO.pipe

			pid = Process.spawn(
			 "/usr/bin/ssh-agent -s -a #{TMPD_S}/ssh-agent-sock",
			 out: w, # 標準出力をパイプにリダイレクト
			 err: w, # 標準エラーをパイプにリダイレクト
			 close_others: true # 必要なファイルディスクリプタ以外を閉じる
			)

			w.close # 書き込み側を閉じる

			r.each_line do |line|
				p line
				if line =~ /SSH_AUTH_SOCK=(.*?)(;|$)/
					@sock = $1
				end
				if line =~ /SSH_AGENT_PID=(.*?)(;|$)/
					@pid = $1
				end
			end

			r.close # 読み取り側を閉じる

			Process.wait(pid.to_i) # 子プロセスの終了を待つ

			if !@sock || !@pid
			   userPrompt :msg, "ERROR: cannot start ssh-agent."
			   exit 1
			end
		end
	end
	def pid
		p
		@pid ||= self.class.created.pid
	end
	def sock
		p
		@sock ||= self.class.created.sock
	end
	def self.created
		@@created ||= self.new(:create)
	end
end

def find_running_ssh_agents
  agents = []
  my_uid = Process.uid

  Dir.glob("/proc/[0-9]*") do |proc_dir|
    pid = proc_dir.split("/").last.to_i
    
    # 自分の所有プロセスかチェック
    next unless (File.stat(proc_dir).uid rescue nil) == my_uid

    # プロセス名が ssh-agent かチェック
    comm = File.read("#{proc_dir}/comm").strip rescue next
    next unless comm == "ssh-agent"

    # コマンドライン引数をパース
    cmdline = File.read("#{proc_dir}/cmdline").split("\0") rescue next
    
    # -a で指定されたソケットパスがあれば取得
    sock_path = nil
    if (idx = cmdline.index("-a"))
      sock_path = cmdline[idx + 1]
    end
	 a = SSHAgent.new(pid, sock_path, cmdline)
		if sock_path == ENV['SSH_AUTH_SOCK']
			agents.unshift a
		else
			agents << a
		end
  end
  agents + [NewAgent.new]
end

def getkeylist
	require 'open3'

	stdout, stderr, status = Open3.capture3("ssh-add", "-l")

	case status.exitstatus
	when 0
	  # 正常：鍵が存在する（stdout の各行をパース）
	  keys = stdout.lines.map { |line| line.split[1] } # SHA256:... を抽出
	when 1
	  # 正常だが鍵が0件 ("The agent has no identities.")
	  keys = []
	when 2
	  # 異常：agentに接続できない（stderr にエラー内容）
	  # warn "Agent error: #{stderr.strip}"
	end
	keys
end


def getKeyListInSSHAgent
   keylist = []
	agents = find_running_ssh_agents
	agents.each do |a|
	   ENV['SSH_AUTH_SOCK'] = a.sock
   	ENV['SSH_AGENT_PID'] = a.pid.to_s
		kl = getkeylist
		return kl if kl
	end
	userPrompt :msg, "ERROR: cannot start ssh-agent."
	exit 1
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



