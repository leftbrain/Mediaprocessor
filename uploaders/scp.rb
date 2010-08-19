uploader :scp do |message, config|
  message[:file].seek 0
  require "tempfile" unless defined? Tempfile
  file = Tempfile.open(File.basename(message[:destination][:path]))
  file.binmode
  file.write message[:file].read
  file.flush

  login_at_host = message[:destination][:host]
  if message[:destination][:user]
    login_at_host = "#{message[:destination][:user]}@#{login_at_host}"
  end

  scp_exitstatus, scp_output =
    run_shell_command "scp #{file.path} #{login_at_host}:#{message[:destination][:path]}"

  if scp_exitstatus
    add_result({:destination => message[:destination],
                 :original => message[:original],
                 :notifier => message[:notifier]})
  else
    add_error({error: "scp error: #{scp_output}", original: message[:original]})
  end
end
