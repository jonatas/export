require 'concurrent-edge'

module Export
  # This is responsible for managing the comunication
  class Broadcast
    InvalidChannel = Class.new(StandardError)
    def initialize(&block)
      @channel = {}
      @listener = {}
      instance_exec(&block)
      Concurrent::Channel.go { start_consumer }
    end

    def on(event, &block)
      @channel[event] = Concurrent::Channel.new
      @listener[event] = block
    end

    def publish(event, *data)
      unless @channel.key?(event)
        raise InvalidChannel, "Unrecognized #{event}. Currently allowed: #{@channel.keys.join(', ')}."
      end
      @channel[event] << data
    end

    def start_consumer
      @channel.each do |event, channel|
        Thread.new(event, channel) do |evt, ch|
          loop do
            next unless (data = ~ch)

            begin
              @listener[evt].call(*data)
            rescue
              puts "Ops! Error consuming #{evt} with #{data}. #{$ERROR_INFO}", $ERROR_POSITION
            end
          end
        end
      end
    end
  end
end
