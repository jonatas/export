require 'concurrent-edge'

module Export
  class Broadcast
    InvalidChannel = Class.new(StandardError)
    def initialize &block
      @channel = {}
      @listener = {}
      instance_exec(&block)
      Concurrent::Channel.go { start_consumer  }
    end

    def on event, &block
      @channel[event] = Concurrent::Channel.new
      @listener[event] = block
    end

    def publish event, *data
      unless @channel.has_key?(event)
        raise InvalidChannel.new("Unrecognized #{event}. Currently allowed: #{@channel.keys.join(', ')}.")
      end
      @channel[event] << data
    end

    def start_consumer
      @channel.each do |event, channel|
        Thread.new(event, channel) do |evt,ch|
          while true
            if data = ~ch
              begin
                @listener[evt].call(*data)
              rescue
                puts "Ops! Error consuming #{evt} with #{data}. #{$!}", $@
              end
            end
          end
        end
      end
    end
  end
end
