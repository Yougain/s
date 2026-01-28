class IO
    def set_writer(w)
        @writer = w
        @buffers = []
        @mutex = Mutex.new
        @condition = ConditionVariable.new
    end

    def transfer
        if @writer
            @mutex.synchronize do
                begin
                    @buffers.push readpartial(1024)
                rescue EOFError
                    @buffers.push nil
                    @eof = true
                end
                @condition.signal # バッファに要素が追加されたことを通知
            end
            @thread ||= Thread.new do
                catch :exit do
                    loop do
                        data = nil
                        @mutex.synchronize do
                            while @buffers.empty?
                                @condition.wait(@mutex) # バッファに要素が追加されるまで待機
                            end
                            data = @buffers.shift
                            if data.nil?
                                throw :exit
                            end                            
                        end
                        check_line data
                        @writer.write data
                        @writer.flush
                    end
                end
            end
        end
    end
    def check_line data
    end
    def eof?
        @eof
    end
    def join
        @thread.join if @thread
    end
end


def proot_server
    ARGV.shift
    user = ARGV.shift
    if ARGV.empty?
        s = get_login_shell_from_passwd user
        if s
            ARGV << s
            ARGV << "-i"
        else
            ARGV << "bash"
            ARGV << "-i"
        end
    end
    inserter = %W{proot-distro login ubuntu --no-arch-warning --bind /dev/null:/etc/mtab --user #{user} --}
    cmd = [*inserter, *ARGV]
    if STDIN.tty?
        exec *cmd
    else
        Open3.popen3 *cmd do |stdin, stdout, stderr, wait_thr|
            def stderr.check_line data
                !data.gsub! /^proot warning:.*?\n/, ""
            end
            stdin.set_encoding("ASCII-8BIT")
            stdout.set_encoding("ASCII-8BIT")
            stderr.set_encoding("ASCII-8BIT")
            stdin.sync = true
            stdout.sync = true
            stderr.sync = true
            STDIN.set_writer stdin
            stdout.set_writer STDOUT
            stderr.set_writer STDERR
            rarr = []
            loop do
                rarr.push stdout if !stdout.eof?
                rarr.push stderr if !stderr.eof?
                rarr.push STDIN
                break if rarr == [STDIN]
                rs, = IO.select(rarr)
                rs.each do |r|
                    r.transfer
                end
                rarr.clear
            end
            [stdout, stderr].each do |f|
                f.join
            end
        end
    end

end

def get_login_shell_from_passwd(username)
    begin
      File.foreach('/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/etc/passwd') do |line|
        fields = line.split(':')
        if fields[0] == username
          return fields[6].strip # ログインシェルのフィールドを返す
        end
      end
      nil # ユーザーが見つからない場合
    rescue Errno::ENOENT
      nil # /etc/passwdが存在しない場合
    end
end

