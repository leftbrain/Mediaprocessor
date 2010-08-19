require 'shell_command'
require 's3_uploader'
require 'pid'

require 'monitor'
require "net/http"

module MediaProcessor
  PROCESS_NAME = "media"

  @@config = YAML.load_file(File.join(File.dirname(__FILE__), '..',
                                      'config', 'main.yml'))
  @@config.symbolize_keys!
  @@pid_file = @@config[:pid_path]
  @@logger_file = File.open(File.join(@@config[:logger_path],
                                      "#{PROCESS_NAME}.log"),
                            File::WRONLY | File::APPEND | File::CREAT)
  @@logger_file.sync = true
  @@logger = Logger.new(@@logger_file)
  @@logger.formatter = ->(severity, time, progname, msg) do
    "%s, [%s] %5s -- %28s: %s\n" % [severity[0..0],
                                    time.strftime("%F %H:%M:%S.%3N"),
                                    severity, Thread.current[:name],
                                    msg.to_s]
  end

  def logger
    @@logger
  end

  def self.config
    @@config
  end

  include Pid
  include S3uploader

  # Makes method which creates specified component entity
  # == Parameters:
  # component_name::
  #   A Symbol declaring component name. For example: :worker or :downloader
  def component component_name
    MediaProcessor.module_exec do
      define_method component_name do |name, &block|
        lunch_something component_name, name do |*args|
          reset_results
          block.call args
          logger.debug "results: #{Thread.current[:current_results]}"
          logger.debug "errors: #{Thread.current[:current_errors]}"
        end
      end
    end
  end

  def reset_results
    (Thread.current[:current_results] ||= Array.new).clear
    (Thread.current[:current_errors] ||= Array.new).clear
  end

  # Lunches thread
  # == Parameters
  # type::
  #   Component type
  # name::
  #   Component name
  # block::
  #   Thread block
  def lunch_something type, name, &block
    key = "#{type.id2name}-#{name}".intern
    config = @@config[key].symbolize_keys if @@config.has_key? key

    logger.debug "lunching #{type} #{name} #{config.nil? ? 1 : config[:threads]}"
    ((config && config[:threads]) || 1).times do |counter|
      MediaProcessor.class_variable_get("@@#{type.id2name.pluralize}")[name] <<
        Thread.new do
        Thread.current[:name] = "#{type}-#{name}(#{counter})"
        Thread.current[:type] = type
        Thread.current[:queue] = MediaProcessor.class_variable_get("@@#{type}_queues")[name]
        Thread.current.abort_on_exception = true
        logger.debug "#{type} #{name} #{counter} started"
        while (message = Thread.current[:queue].pop) != :end
          logger.debug "message: #{message}"
          block.call(message, config)
        end
        logger.debug "thread #{Thread.current[:name]} ended"
      end
    end
  end

  # Prepares components
  # == Parameters:
  # components::
  #   An Array of Symbols of components
  def prepare_components components
    # daemonizing
    srand
    safefork and exit
    unless sess_id = Process.setsid
      STDERR.puts "cannot detach from controlling terminal"
    end
    $0 = PROCESS_NAME
    File.umask 0000

    pid_verify(@@pid_file)

    STDOUT.reopen @@logger_file
    STDOUT.sync = true
    STDERR.reopen STDOUT
    STDERR.sync = true

    components.each do |component_sym|
      MediaProcessor.class_variable_set "@@#{component_sym.id2name.pluralize}",
      (Hash.new { |hash, key| hash[key] = Array.new })

      MediaProcessor.class_variable_set "@@#{component_sym.id2name}_queues",
      (Hash.new { |hash, key| hash[key] = Queue.new })

      define_method "#{component_sym.id2name}_queues".intern do
        MediaProcessor.class_variable_get "@@#{component_sym.id2name}_queues"
      end

      component component_sym

      Dir[File.join(File.dirname(__FILE__), '..', component_sym.id2name.pluralize, '**', '*.rb')].
        each { |component_file| load component_file }
    end

    join_threads = Proc.new do |threads|
      threads.each do |thread|
        next if thread[:finishing]
        thread[:queue] << :end
        thread[:finishing] = true
      end
      threads.each(&:join)
    end
    trap("INT") do
      logger.debug "sigint received"
      join_threads.call components.map { |component_sym| MediaProcessor.class_variable_get("@@#{component_sym.id2name.pluralize}") }.
                        map { |threads_hash| threads_hash.values }.flatten
      pid_clean @@pid_file
      exit
    end
    trap("TERM") do
      logger.debug "sigterm received"
      join_threads.call components.map { |component_sym| MediaProcessor.class_variable_get("@@#{component_sym.id2name.pluralize}") }.
                        map { |threads_hash| threads_hash.values }.flatten
      pid_clean @@pid_file
      exit
    end
  end

  def safefork
    tryagain = true

    while tryagain
      tryagain = false
      begin
        if pid = fork
          return pid
        end
      rescue Errno::EWOULDBLOCK
        sleep 5
        tryagain = true
      end
    end
  end
end
