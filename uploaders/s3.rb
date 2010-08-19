uploader :s3 do |message, config|
  message[:file].seek 0
  if upload_to_s3(config[:access_key_id], config[:secret_access_key], message[:file].read, message[:destination][:path], message[:destination][:bucket]) != :error
    add_result({:destination => message[:destination],
                 :original => message[:original],
                 :notifier => message[:notifier],
                 :file_parameters => message[:file_parameters]})
  else
    add_error({:error => "s3 error: ...",
                :original => message[:original]})
  end
end
