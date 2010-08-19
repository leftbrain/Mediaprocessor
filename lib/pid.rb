module Pid
  def pid_verify pid_file
    if File.exist? pid_file
      if pid_check(File.open(pid_file).read)
        puts 'another process is running, not started'
        exit
      else
        puts 'cleaning pid file'
        pid_clean pid_file
        pid_save pid_file
      end
    else
      pid_save pid_file
    end
  end

  def pid_check pid
    begin
      Process.kill(0, pid.to_i)
    rescue Errno::ESRCH
      return false
    end
  end

  def pid_save pid_file
    fp = File.new(pid_file, File::CREAT|File::RDWR)
    fp.write(Process.pid)
    fp.close
  end

  def pid_clean pid_file
    begin
      File.delete pid_file
    rescue Errno::ENOENT
      return true
    end
  end
end
