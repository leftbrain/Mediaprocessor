notifier :sample_notifier do |message, config|
  notification, results, errors =
    message[:spec], message[:results], message[:errors]

  if errors.nil? or errors.empty?
    logger.debug RestClient.post notification[:response_to], {:destination => notification[:destination],
      :status => "ready"}
  else
    logger.debug RestClient.post notification[:response_to], {:destination => notification[:destination],
      :status => "error",
      :description => errors.inspect}
  end
end

