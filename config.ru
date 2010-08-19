require "main.rb"
log = ::File.new(::File.join(MediaprocessorApi.config["logger_path"], "media_api.log"), "a+")
$stdout.reopen log
$stderr.reopen log
run MediaprocessorApi
