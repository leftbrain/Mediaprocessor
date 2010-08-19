downloader :http do |message, config|
  result = message.clone
  begin
    res = Net::HTTP.start(message[:source][:host],
                          message[:source][:port]) do |http|
      http.get message[:source][:path]
    end
    result[:file] = StringIO.new res.body
    result[:original] = message[:destination]
    res.value
    add_result result
  rescue => e
    add_result_spec({:destination => message[:destination],
                      :all_files => 1,
                      :media_type => message[:notifier],
                      :notifier => message[:notifier],
                      :code => message[:code]})

    add_error({:error => "downloader error: #{e}",
                :original => message[:destination]})
  end
end
