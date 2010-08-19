worker :video do |message, config|
  formats = (message[:formats]["format"].instance_of?(Hash) ?
             [message[:formats]["format"]] : message[:formats]["format"])+
    (message[:formats].has_key?("original_format") ? [:original_format] : [])

  all_files = formats.size + formats.inject(0) do |acc, f|
    if f != :original_format and f.has_key?("stills") and f["stills"].has_key?("still")
      if f["stills"]["still"].instance_of?(Hash)
        acc + 1
      else
        acc + f["stills"]["still"].size
      end
    else
      acc
    end
  end

  video_parameters = {width: 0, height: 0, size: 0, fps: 0, length: 0}

  ffmpeg_exitstatus, ffmpeg_output =
    run_shell_command("ffmpeg -i #{message[:source][:path].inspect}")

  if ffmpeg_output =~ /Duration: ([\d][\d]):([\d][\d]):([\d][\d]).([\d]+)/
    hours = $1
    mins = $2
    seconds =$3
    fractions = $4
    video_parameters[:length] =
      hours.to_i * 60 * 60 + mins.to_i * 60 + seconds.to_i
  end

  if ffmpeg_output =~
      /Stream #0.\d.*: Video:.*[, ](\d+)x(\d+).*[, ](\d+\.?\d*) fps/
    video_parameters[:width] = $1
    video_parameters[:height] = $2
    video_parameters[:video_fps] = $3
  end

  if ffmpeg_output =~ /Stream #0.\d.*: Audio: .* (\d+) kb\/s.*/
    video_parameters[:audio_quality] = $1
  end

  video_parameters[:size] = (message[:file].size - 1) / 1024 + 1

  add_result_spec ({:destination => message[:original],
                     :all_files => all_files,
                     :media_type => :video,
                     :notifier => message[:notifier],
                     :code => message[:code],
                     :response_to => message[:response_to]})

  ext = message[:source][:path][/.*(\.[^.]+)/, 1]
  source_file = Tempfile.new(["original_video", ext])
  source_file.binmode
  message[:file].seek 0
  source_file.write message[:file].read
  source_file.flush

  formats.each do |format|
    suffix = nil

    if format.instance_of? Hash
      suffix = format["suffix"]
      format.symbolize_keys!
    end

    result = {:uploader => message[:uploader],
      :original => message[:original]}

    output_file = nil
    if format != :original_format
      output_file = Tempfile.new(["video", ".#{format[:extension]}"])

      parameters = ["-ab 65k -ar 22050 -ac 1 -acodec libmp3lame "]
      parameters << "-t #{format[:length]} " if
        format.has_key?(:length) and format[:length] != "original"
      parameters << "-r #{format[:fps]} " if
        format.has_key?(:fps) and format[:fps] != "original"
      parameters << "-s #{format[:width]}x#{format[:height]} " if
        format.has_key?(:width) and format.has_key?(:height) and
        format[:width] != :original and format[:height] != "original"
      parameters << "-b 204800 "

      ffmpeg_exitstatus, ffmpeg_output =
        run_shell_command("ffmpeg -y -i #{source_file.path} " \
                          "#{parameters.join}" \
                          "#{output_file.path.inspect}")

      unless ffmpeg_exitstatus
        logger.error "ffmpeg error during resizing movie: #{ffmpeg_output}"
        add_error({error: "ffmpeg error during resizing movie", original: message[:destination]})
        next
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
                              :file_parameters => video_parameters})


    if format != :original_format and format.has_key?(:stills) and format[:stills].has_key?("still")
      frame_output_file = Tempfile.new(["video", ".jpg"])
      ffmpeg_exitstatus, ffmpeg_output =
        run_shell_command("ffmpeg -y -i #{output_file.path.inspect} " \
                          "-ss #{video_parameters[:length] * 0.25} " \
                          "-vframes 1 -f image2 " \
                          "#{frame_output_file.path.inspect}")

      (format[:stills]["still"].instance_of?(Hash) ?
       [format[:stills]["still"]] : format[:stills]["still"]).each do |still|
        still.symbolize_keys!

        if not ffmpeg_exitstatus or not File.exists? frame_output_file.path or frame_output_file.size == 0
          add_error({error: "ffmpeg error during creating frame", original: message[:destination]})
          logger.error "ffmpeg error during creating frame: #{ffmpeg_output}"
        else
          image = Magick::Image.read(frame_output_file.path).first
          if still.has_key?(:keep_ratio) and still[:keep_ratio] == "false"
            image.resize!(still[:width].to_i, still[:height].to_i) if
              still[:width].to_i > 0 and still[:height].to_i > 0
          else
            image.resize_to_fit!(still[:width].to_i, still[:height].to_i) if
              still[:width].to_i > 0 and still[:height].to_i > 0
          end

          image_dest = message[:destination].clone
          if still[:destination]
            still_uri = Addressable::URI.parse still[:destination]
            image_dest = still_uri.to_hash
            if image_dest[:scheme] == "s3"
              image_dest[:bucket] = image_dest.delete :host
            end
          end

          image_dest[:path] = "#{image_dest[:path][/(.*)\.[a-zA-Z0-9]+/, 1]}" \
          "#{still[:suffix]}.jpg"
          image_output = StringIO.new(image.to_blob {format = "JPG"})
          add_result({:uploader => message[:uploader],
                       :file => image_output,
                       :original => message[:original],
                       :destination => image_dest})
        end
      end
    end
  end
end
