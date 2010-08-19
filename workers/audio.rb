worker :audio do |message, config|
  formats = (message[:formats]["format"].instance_of?(Hash) ?
             [message[:formats]["format"]] : message[:formats]["format"]) +
    (message[:formats].has_key?("original_format") ? [:original_format] : [])

  audio_parameters = {width: 0, height: 0, size: 0, fps: 0, length: 0}
  ext = message[:source][:path][/.*(\.[^.]+)/, 1]
  source_file = Tempfile.new(["original_audio", ext])
  source_file.binmode
  message[:file].seek 0
  source_file.write message[:file].read
  source_file.flush

  ffmpeg_exitstatus, ffmpeg_output =
    run_shell_command("ffmpeg -i #{source_file.path}")
  duration_in_miliseconds = nil
  if ffmpeg_output =~ /Duration: ([\d][\d]):([\d][\d]):([\d][\d]).([\d]+)/
    hours = $1
    mins = $2
    seconds =$3
    fractions = $4
    audio_parameters[:length] =
      hours.to_i * 60 * 60 + mins.to_i * 60 + seconds.to_i
    duration_in_miliseconds = ((hours.to_i.hours +
                                mins.to_i.minutes +
                                seconds.to_i +
                                "0.#{fractions}".to_f.seconds) * 1000).to_i
  end

  if ffmpeg_output =~ /Stream #0.\d.*: Audio: .* (\d+) kb\/s.*/
    audio_parameters[:audio_quality] = $1
  end

  audio_parameters[:size] = (source_file.stat.size - 1) / 1024 + 1

  add_result_spec({:destination => message[:original],
                    :all_files => formats.length,
                    :media_type => :audio,
                    :notifier => message[:notifier],
                    :code => message[:code],
                    :response_to => message[:response_to]})

  result = {:uploader => message[:uploader],
    :original => message[:original]}

  formats.each do |format|
    suffix = nil

    if format.instance_of? Hash
      suffix = format["suffix"]
      format.symbolize_keys!
    end

    output_file = nil

    if format != :original_format
      output_file = Tempfile.new(["audio", ".#{format[:extension]}"])

      parameters = []
      parameters << "-acodec #{format[:codec]} " if
        format.has_key?(:codec) and format[:codec] != "original"
      parameters << "-ab #{format[:audio_quality]}k " if
        format.has_key?(:audio_quality) and format[:audio_quality] != "original"
      parameters << "-f #{format[:format]} " if
        format.has_key?(:format) and format[:format] != "original"

      if format.has_key?(:length) and format[:length] != "original"
        parameters << "-t #{format[:length]} "
        length_in_miliseconds = nil
        if format[:length] =~ /([\d][\d]):([\d][\d]):([\d][\d]).([\d]+)/
          hours = $1
          mins = $2
          seconds =$3
          fractions = $4
          length_in_miliseconds = ((hours.to_i.hours + mins.to_i.minutes + seconds.to_i + "0.#{fractions}".to_f.seconds) * 1000).to_i
        elsif format[:length].to_i != 0
          parameters << "-metadata TIME=#{format[:length].to_i * 1000} "
        end
      elsif duration_in_miliseconds
        parameters << "-metadata TIME=#{duration_in_miliseconds} "
      end

      ffmpeg_exitstatus, ffmpeg_output =
        run_shell_command("ffmpeg -y -i #{source_file.path.inspect} " \
                          "#{parameters.join}" \
                          "#{output_file.path.inspect}")

      unless ffmpeg_exitstatus
        logger.warn ffmpeg_output
        add_error({:error => "ffmpeg error during processing audio file",
                    :original => message[:original]})
      end
    else
      output_file = source_file
    end
    destination = message[:destination].clone
    destination[:path] = case format
           when :original_format then message[:destination][:path]
           else "#{message[:destination][:path][/(.*)\.[a-zA-Z0-9]+/, 1]}#{suffix}." \
             "#{format[:extension]}"
           end

    add_result result.merge({:file => output_file,
                              :destination => destination,
                              :file_parameters => audio_parameters})
  end
end
