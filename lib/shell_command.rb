def run_shell_command cmd, timeout = 5.minutes
  require 'timeout' unless defined? Timeout

  if RUBY_VERSION < "1.9"
    require 'popen4' unless defined? POpen4
    stdoutstring = nil
    stderrorstring = nil
    Timeout::timeout(timeout) do
      status = POpen4.popen4(cmd) do |stdout, stderr, stdin, pid|
        stdoutstring = stdout.read
        stderrorstring = stderr.read
      end
      if status.success?
        [true, stdoutstring]
      else
        [false, stderrorstring]
      end
    end
  else
    require 'open3' unless defined? Open3
    Timeout::timeout(timeout) do
      Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        wait_thr.join

        if wait_thr.value.success?
          [true, stdout.read]
        else
          [false, stderr.read]
        end
      end
    end
  end
rescue Timeout::Error => e
  [false, "timeout #{timeout} has been exceeded"]
end
