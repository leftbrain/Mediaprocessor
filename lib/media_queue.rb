module MediaQueue
  class Element
    def initialize
    end
  end

  class Queue
    def initialize media_queue_file
      require "pstore" unless defined? PStore
      if RUBY_VERSION < "1.9"
        @storage = PStore.new media_queue_file
      else
        @storage = PStore.new media_queue_file, true
      end
      @storage.transaction do
        @storage[:last_elem] ||= 0
        @storage[:elements] ||= Array.new
      end
    end

    def size
      result = 0
      @storage.transaction(true) do
        result = @storage[:elements].size
      end
      result
    end

    def shift(keep = false)
      result = nil
      @storage.transaction do
        result = @storage[:elements].shift
      end
      result
    end

    def pop(keep = false)
      result = nil
      @storage.transaction do
        result = @storage[:elements].pop
      end
      result
    end

    def push element
      @storage.transaction do
        @storage[:elements] << element
      end
    end

    alias_method :<<, :push

    def remove element
    end

    def clear
      @storage.transaction do
        @storage[:element].clear
      end
    end
  end
end
