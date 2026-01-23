PassPhrase = ""
IdFile = ""

def createKey
    if !system "SSH_ASKPASS=\"\" " + ["ssh-keygen", "-t", "ed25519", "-f", "#{ENV['HOME']}/.ssh/id_ed25519", "-N", PassPhrase].shelljoin
        Cout.puts "ERROR: cannot create key."
        exit 1
    end
    IdFile.replace "#{ENV['HOME']}/.ssh/id_ed25519"
end



def key_has_passphrase?(key_path)
    output = ""
    PTY.spawn "SSH_ASKPASS=\"\" " + ["ssh-keygen", "-y", "-f", key_path].shelljoin do |r, w, pid|
        select [r]
        out = r.readpartial(1024) rescue nil
        if out
            output << out if out
            if out =~ /Enter passphrase for key/
                w.write "\r\n"
                w.flush
            end
            Process.kill :TERM, pid
        end
        Process.wait pid
    end

    output.include?("Enter passphrase")
end

def createPassPhrase
    passPhrase = []
    loop do
        passPhrase << userPrompt(:passwd, "#{passPhrase.size == 0 ? 'E' : 'Ree'}nter passphrase for key: ")
        if passPhrase.size == 1 && passPhrase[0].empty?
            if userPrompt :yn, "Empty passphrase. Are you sure?"
                PassPhrase.replace ""
                break
            else
                exit 1
            end
        elsif passPhrase.size == 2
            if passPhrase[0] == passPhrase[1]
                PassPhrase.replace passPhrase[0]
                break
            else
                userPrompt :msg, "ERROR: passphrase not match."
                exit 1
            end
        end
    end
end

def installKey sshc, pw, key
    cmd = "if [ ! -e ~/.ssh ];then mkdir -m 0700 ~/.ssh;fi;touch ~/.ssh/authorized_keys;chmod 600 ~/.ssh/authorized_keys;perl -i.bak -ne \"print unless(\\\$_ eq '#{key.chomp}' . chr(0x0a))\" ~/.ssh/authorized_keys;echo '#{key.chomp}' >> ~/.ssh/authorized_keys"
    sshCommand sshc, ["bash", "-c", [cmd].shelljoin] do |line, w|
        case line
        when /'s password: /
            w.write pw + "\r\n"
            w.flush
        end
    end or (
        userPrompt :msg, "ERROR: cannot install key."
        exit 1
    )
end

def createAndInstallKey sshc, dest
    FileUtils.mkdir_p "#{ENV['HOME']}/.ssh"
    FileUtils.chmod 0700, "#{ENV['HOME']}/.ssh"
    pw = userPrompt :passwd, "#{dest}'s password:"
    if doCheck(sshc, dest, [], {}, pw).values_at(-2, -1) != [:password, :success]
        userPrompt :msg, "ERROR: password for #{dest} is not correct."
        exit 1
    end
    if !File.exist? "#{ENV['HOME']}/.ssh/id_ed25519.pub"
        createPassPhrase
        createKey
    end
    installKey sshc, pw, IO.read("#{ENV['HOME']}/.ssh/id_ed25519.pub")
end


