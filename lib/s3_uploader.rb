module S3uploader
  def upload_to_s3 access_key_id, secret_access_key, content, key_value, bucket_name
    key_value = key_value[/\/(.*)/, 1]
    logger.debug [access_key_id, secret_access_key, key_value, bucket_name].join " "
    s3 = Aws::S3.new(access_key_id, secret_access_key,
                {:multi_thread => true,
                  :logger => logger
                })
    retry_counter = 0
    begin
      retry_counter += 1
      bucket = s3.bucket(bucket_name)
      logger.debug "key_value: #{key_value}"
      bucket.put(key_value, content, {}, 'public-read')
    rescue Aws::AwsError => e
      logger.debug "aws error #{e}"
      if !e.errors.instance_of? String and e.errors.map(&:first).include? "NoSuchBucket"
        if @@create_bucket_semaphores[bucket_name].try_lock
          logger.debug "creating bucket"
          s3.interface.create_bucket bucket_name
          @@create_bucket_semaphores[bucket_name].unlock
        else
          sleep 3
        end
        retry
      else
        if retry_counter < 5
          logger.warn "retrying on error... #{retry_counter}"
          sleep 3
          retry
        end
      end

      logger.error "aws error: #{e}"
      return :error
    rescue => e
      logger.error "aws error: #{e}"
      rescue :error
    end
  end

  def logger
    @@logger
  end

  def self.included mod
    @@create_bucket_semaphores = Hash.new { |hash, key| hash[key] = Mutex.new }
    @@create_bucket_semaphore = Mutex.new
    @@logger = mod.class_variable_get(:@@logger)
  end
end
