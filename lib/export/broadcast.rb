require 'thread'
module Export
  class Broadcast
    InvalidChannel = Class.new(StandardError)
    def initialize &block
      @q = Queue.new
      @listeners = {}
      instance_exec(&block) if block_given?
    end

    def on event, &block
      @listeners[event] = block
    end

    def publish event, *data
      @q << [event, data]
    end

    def start_consumer
      Thread.new do
        begin
          resume_work
        rescue
          puts "Ops! error on consumer: #{$!}",$@
        end
      end
    end

    def resume_work
      opened = []
      while (@q.size > 0)
        event, data = @q.pop
        unless @listeners.has_key?(event)
          raise InvalidChannel.new("Unrecognized #{event}. Currently allowed: #{@listeners.keys.join(', ')}")
        end
        opened << Thread.new(event, data) do |evt, d|
          begin
            @listeners[evt].call(d)
          rescue
            puts "Ops! Error on #{evt} listener: #{$!}",$@
          end
        end

        if opened.size > 10
          opened.each(&:join)
          opened = []
        end
      end
      opened.each(&:join)
      resume_work if @q.size > 0
    end
  end
end
