downloader :file do |message, config|
  result = message.clone

  if File.exist? message[:source][:path]
    result[:file] = StringIO.new File.read(message[:source][:path])
    result[:original] = message[:destination]
    add_result result
  else
    add_result_spec({:destination => message[:destination],
                    :all_files => 1,
                    :media_type => message[:worker],
                    :notifier => message[:notifier],
                    :code => message[:code]})

    add_error({:error => "downloader error: no such file: #{message[:source][:path]}",
                :original => message[:destination]})
  end
end
