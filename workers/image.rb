worker :image do |message, config|
  formats = (message[:formats]["format"].instance_of?(Hash) ?
             [message[:formats]["format"]] : message[:formats]["format"]) +
    (message[:formats].has_key?("original_format") ? [:original_format] : [])

  add_result_spec({:destination => message[:original],
                    :all_files => formats.length,
                    :media_type => :image,
                    :notifier => message[:notifier],
                    :code => message[:code],
                    :response_to => message[:response_to]})

  result = {:uploader => message[:uploader],
    :original => message[:original]}

  formats.each do |params|
    suffix = nil

    if params.instance_of? Hash
      suffix = params["suffix"]
      params.symbolize_keys!
    end

    image = nil
    begin
      message[:file].seek 0
      image = Magick::Image.from_blob(message[:file].read).first
      if params != :original_format and
          params[:width].to_i > 0 and params[:height].to_i > 0
        if params.has_key?(:crop_middle) and params[:crop_middle] == "true"
          original_width = image.columns
          original_height = image.rows
          if original_width > original_height # szersze niz wyzsze
            scale = params[:height].to_f / original_height
            image.resize!(scale)
            image.crop!((image.columns - params[:width].to_i) / 2, 0, params[:width].to_i, params[:height].to_i)
          else
            scale = params[:width].to_f / original_width
            image.resize!(scale)
            image.crop!(0, (image.rows - params[:height].to_i) / 2, params[:width].to_i, params[:height].to_i)
          end
        else
          if params.has_key?(:keep_ratio) and params[:keep_ratio] == "false"
            image.resize!(params[:width].to_i, params[:height].to_i)
          else
            image.resize_to_fit!(params[:width].to_i, params[:height].to_i)
          end
        end
      end
      image_parameters = {width: image.columns,
        height: image.rows,
        size: ((image.filesize - 1) / 1024 + 1)}
      destination = message[:destination].clone
      destination[:path], output = case params
             when :original_format then [message[:destination][:path],
                                         message[:file]]
             else ["#{destination[:path][/((?:\/[^\/]*)*\/.*)\.[a-zA-Z0-9]+/, 1]}#{suffix}.jpg",
                   StringIO.new(image.to_blob {format = "JPG"})]
             end
      add_result result.merge({:file => output,
                                :destination => destination,
                                :file_parameters => image_parameters})
    rescue Magick::ImageMagickError => e
      logger.error "image magick error: #{e}"
      add_error({:error => "image magick error: #{e}", :original => message[:original]})
    end
  end
end
