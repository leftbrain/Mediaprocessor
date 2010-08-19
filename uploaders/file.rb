uploader :file do |message, config|
  message[:file].seek 0
  begin
    File.open(message[:destination][:path], "w") do |file|
      file.write message[:file].read
    end

    add_result message.merge({:destination => message[:destination],
                               :original => message[:original],
                               :notifier => message[:notifier],
                               :file_parameters => message[:file_parameters]})
  rescue => e
    add_error({:error => "file error: #{e}", :original => message[:original]})
  end
end
