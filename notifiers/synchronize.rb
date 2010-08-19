notifier :synchronize do |message, config|
  synchro = PStore.new config[:sync_state_file], true
  notification, results, errors =
    message[:spec], message[:results], message[:errors]

  synchro.transaction do
    if synchro[notification[:code]]
      if errors.nil? or errors.empty?
        synchro[notification[:code]] = :ready
      else
        synchro[notification[:code]] = [:error, errors.inspect.encode("utf-8", :invalid => :replace, :undef => :replace)]
      end
    end
  end
end
