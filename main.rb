require "bundler"
Bundler.setup :default, :api
require "sinatra"
require "xmlsimple"

require "lib/media_queue"
require "timeout"
require "pstore"
require "yaml"
require "logger"
require "addressable/uri"

class MediaprocessorApi < Sinatra::Application
  def self.config
    @@config ||= YAML.load_file(File.join(File.dirname(__FILE__),
                                          'config', 'main.yml'))
  end

  configure do
    LOGGER = Logger.new(File.join(config["logger_path"], "media_api.log"))
  end

  helpers do
    def logger
      LOGGER
    end

    def validate_uri uri, type
      begin
        parsed_uri = Addressable::URI.parse uri
        logger.debug "#{type}-#{parsed_uri.scheme}"
        if parsed_uri.scheme.nil? or not File.exists?(File.join type, "#{parsed_uri.scheme}.rb")
          logger.debug "invalid uri #{uri}"
          return false
        end
      rescue Addressable::URI::InvalidURIError => e
        logger.debug "invalid uri #{uri} - exception: #{e}"
        return false
      end
      return true
    end
  end

  def media_queue
    @@media_queue ||= MediaQueue::Queue.new MediaprocessorApi.config["media_queue_file"]
  end

  def synchronize_codes
    if RUBY_VERSION < "1.9"
      @@synchronize_codes ||= PStore.new MediaprocessorApi.config["notifier-synchronize"]["sync_state_file"]
    else
      @@synchronize_codes ||= PStore.new MediaprocessorApi.config["notifier-synchronize"]["sync_state_file"], true
    end
  end

  get "/" do
    "it works"
  end

  put "/media/create" do
    source_uri_is_valid = true
    destination_uri_is_valid = true
    XmlSimple.xml_in(request.env["rack.input"].read, 'ForceArray' => false).each do |media_type, media_spec|
      logger.debug "media/create request: #{media_spec.inspect}"

      source_uri_is_valid = validate_uri media_spec["source"], "downloaders"
      destination_uri_is_valid = validate_uri media_spec["destination"], "uploaders"

      if source_uri_is_valid and destination_uri_is_valid
        media_queue << media_spec.merge({"type" => media_type})
      end
    end

    if source_uri_is_valid and destination_uri_is_valid
      XmlSimple.xml_out({"type" => ["ok"]},
                        "RootName" => ["response"])
    else
      unless source_uri_is_valid or destination_uri_is_valid
        XmlSimple.xml_out({"type" => ["error"],
                            "description" => ["invalid source and destination uri"]},
                          "RootName" => "response")
      else
        unless source_uri_is_valid
          logger.debug "invalid source uri"
          XmlSimple.xml_out({"type" => ["error"],
                              "description" => ["invalid source uri"]},
                            "RootName" => "response")
        else
          logger.debug "invalid destination uri"
          XmlSimple.xml_out({"type" => ["error"],
                              "description" => ["invalid destination uri"]},
                            "RootName" => "response")
        end
      end
    end
  end

  put "/media/fetch" do
    code = nil
    if RUBY_VERSION < "1.9"
      code = (('a'..'z').to_a + 0.upto(10).to_a).shuffle.first(20).join
    else
      code = (('a'..'z').to_a + 0.upto(10).to_a).sample(20).join
    end

    source_uri_is_valid = true
    destination_uri_is_valid = true
    XmlSimple.xml_in(request.env["rack.input"].read, 'ForceArray' => false).each do |media_type, media_spec|
      logger.debug "media/fetch request #{media_spec.inspect}"

      source_uri_is_valid = validate_uri media_spec["source"], "downloaders"
      destination_uri_is_valid = validate_uri media_spec["destination"], "uploaders"

      if source_uri_is_valid and destination_uri_is_valid

        synchronize_codes.transaction do
          synchronize_codes[code] = :processing
        end

        media_queue << media_spec.merge({"type" => media_type, :notifier => :synchronize, :code => code})
      end
    end

    if source_uri_is_valid and destination_uri_is_valid
      begin
        t = nil
        Timeout::timeout(60) do
          t = Time.now
          finished = false
          result = nil
          until finished do
            synchronize_codes.transaction do
              result = synchronize_codes[code]
              finished = synchronize_codes[code] != :processing
            end
            sleep 0.1
          end
          if result == :ready
            logger.debug "fetch (media ready) time: #{Time.now - t}s"
            XmlSimple.xml_out({"type" => ["ok"]},
                              "RootName" => ["response"])
          elsif result.instance_of?(Array) and result.first == :error
            logger.debug "fetch (media error) time: #{Time.now - t}s"
            XmlSimple.xml_out({"type" => ["error"],
                                "description" => [result.last]},
                              "RootName" => "response")
          end
        end
      rescue Timeout::Error
        logger.warn "timeout!"
        XmlSimple.xml_out({"type" => ["error"],
                            "description" => ["timeout error"]},
                          "RootName" => "response")
      end
    else
      unless source_uri_is_valid or destination_uri_is_valid
        logger.debug "sending error (invalid both uri)"
        XmlSimple.xml_out({"type" => ["error"],
                            "description" => ["invalid source and destination uri"]},
                          "RootName" => "response")
      else
        unless source_uri_is_valid
          logger.debug "sending error (invalid source uri)"
          XmlSimple.xml_out({"type" => ["error"],
                              "description" => ["invalid source uri"]},
                            "RootName" => "response")
        else
          logger.debug "sending error (description source uri)"
          XmlSimple.xml_out({"type" => ["error"],
                              "description" => ["invalid destination uri"]},
                            "RootName" => "response")
        end
      end
    end
  end
end
