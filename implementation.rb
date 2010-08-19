module Implementation
  @@file_counter = Hash.new { |hash, key| hash[key] = Array.new }
  @@file_counter.extend(MonitorMixin)

  @@error_counter = Hash.new { |hash, key| hash[key] = Array.new }
  @@error_counter.extend(MonitorMixin)

  @@result_spec = Hash.new
  @@result_spec.extend(MonitorMixin)

  def process message
    message.symbolize_keys!
    source_uri = Addressable::URI.parse message[:source]
    uploader_uri = Addressable::URI.parse message[:destination]

    if not downloader_queues.has_key? source_uri.scheme.intern
      logger.error "bad downloader name: #{source_uri.scheme} in message: #{message.inspect}"
      return
    end

    if not uploader_queues.has_key? uploader_uri.scheme.intern
      logger.error "bad uploader name: #{uploader_uri.scheme} in message: #{message.inspect}"
      return
    end

    message[:source] = source_uri
    message[:destination] = uploader_uri

    message[:source] = message[:source].to_hash
    message[:destination] = message[:destination].to_hash

    if message[:destination][:scheme] == "s3"
      message[:destination][:bucket] = message[:destination].delete :host
    end

    message[:uploader] = uploader_uri.scheme.intern
    message[:original] = uploader_uri.path
    message[:notifier] = case message[:client]
                         when "sample_client" then :sample_notifier
                         else
                           begin
                             logger.error "unknown client #{message}"
                             return
                           end
                         end
    downloader_queues[source_uri.scheme.intern] << message
  rescue Addressable::URI::InvalidURIError => e
    logger.error "invalid uri in message: #{message.inspect}"
  end


  def add_result_spec spec
    logger.debug "add_result_spec: #{spec.inspect}"
    if [:worker, :downloader].include? Thread.current[:type]
      @@result_spec.synchronize do
        @@result_spec[spec[:destination]] = spec
      end
    end
  end

  def add_result result
    (Thread.current[:current_results] ||= Array.new) << result
    if Thread.current[:type] == :worker
      @@file_counter.synchronize do
        uploader_queues[result[:uploader]] << result
      end
    elsif Thread.current[:type] == :downloader
      @@file_counter.synchronize do
        worker_queues[result[:type].intern] << result
      end
    elsif Thread.current[:type] == :uploader
      @@file_counter.synchronize do
        @@file_counter[result[:original]] << result
      end

      finalize_result_collection result
    end
  end

  def add_error result
    (Thread.current[:current_errors] ||= Array.new) << result
    if Thread.current[:type] == :worker
      @@error_counter.synchronize do
        @@error_counter[result[:original]] << result
      end
    elsif Thread.current[:type] == :downloader
      @@error_counter.synchronize do
        @@error_counter[result[:original]] << result
      end

      finalize_result_collection result
    elsif Thread.current[:type] == :uploader
      @@error_counter.synchronize do
        @@error_counter[result[:original]] << result
      end
    end
    finalize_result_collection result
  end

  def finalize_result_collection result
    @@result_spec.synchronize do
      unless @@result_spec.has_key? result[:original]
        logger.error "result spec does not have key: #{result[:original]} #{@@result_spec.inspect}"
      else
        @@file_counter.synchronize do
          @@error_counter.synchronize do

            if (@@file_counter[result[:original]].length +
                @@error_counter[result[:original]].length) ==
                @@result_spec[result[:original]][:all_files]
              notifier_queues[@@result_spec[result[:original]][:notifier] ||
                                result[:notifier]] <<
                {:spec => @@result_spec[result[:original]],
                :results => @@file_counter[result[:original]],
                :errors => @@error_counter[result[:original]]}
              @@file_counter.delete result[:original]
              @@error_counter.delete result[:original]
              @@result_spec.delete result[:original]
            end
          end
        end
      end
    end
  end
end
