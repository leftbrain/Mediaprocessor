require "rubygems"
require "bundler"
Bundler.setup :default, :processor
require "RMagick"
require "active_support"
require "rest-client"
require "xmlsimple"
require "aws"
require "addressable/uri"
require "addressable/template"

require 'yaml'
require 'logger'
require 'thread'
require 'tempfile'

$:.unshift File.dirname(__FILE__)
$:.unshift File.join(File.dirname(__FILE__), 'lib')

require 'media_processor'
require 'media_queue'
require "implementation"

include MediaProcessor
extend Implementation

MediaProcessor.prepare_components([:worker, :notifier, :uploader, :downloader])

queue = MediaQueue::Queue.new MediaProcessor.config[:media_queue_file]

loop do
  message = queue.shift
  if message.nil?
    sleep 1
    next
  end
  self.logger.debug "message received from queue: #{message}"
  if ["avatar", "image", "video", "audio", "talent_category"].include? message["type"]
    logger.debug "type #{message["type"]} recognized"
    message[:media_queue] = message["type"].intern
    process message
  else
    logger.error "unknown message type"
  end
end

join_threads.call(@@workers.values + @@uploaders.values + @@notifiers.values)
