require 'export/broadcast'

module Export
  class Dump
    attr_reader :options, :exported, :broadcast, :scope

    def initialize(schema, &block)
      @schema = schema
      @scope = {}
      @exported = {}
      @exporting = {}
      @ignore = []
      @queue = Queue.new
      @except_keys = []
      @broadcast = setup_broadcast
      instance_exec(&block) if block_given?
    end

    def setup_broadcast
      Broadcast.new do
        on "fetch" do |model, data|
          puts "Fetched: #{model} with #{data&.length} records"
          if Export.replacements_for(model)
            print " > Transforming..."
            t = Time.now
            data = Export.transform_data(model, data)
            print " done in #{Time.now - t} seconds"
          end
          publish "transform", model, data
        end

        on "transform" do |model, data|
          t = Time.now
          print "\n#{Time.now} #{model} - #{data.size}"
          Dir.mkdir("tmp") unless Dir.exists?("tmp")
          filename = "tmp/#{model.name.underscore.tr('/','__')}.json"
          File.open(filename,"w+"){|f|f.puts data.to_json}
          print " finished #{filename} in #{Time.now - t} seconds. #{File.size(filename)}"
          publish "stored", filename
        end

        on "stored" do |filename|
          puts "add to zip: #{filename}"
        end
      end
    end

    def model name, &block
      @scope[name.to_s] = block
    end

    def ignore *model
      @ignore += [*model]
    end

    def except *keys
      @except_keys += [*keys]
    end

    def fetch
      Export::DependencyTree.interesting_models.each do |model|
        print "Fetching: #{model}"
        t = Time.now
        data = fetch_data(model)
        print " ... #{data&.length || 0} in #{Time.now - t} seconds\n"
      end
    end

    def on_fetch_error(&block)
      @on_fetch_error = block
    end

    def scope_for(clazz)
      Export::DependencyTree.new(clazz).fetch(@scope)
    end

    def fetch_data clazz
      @exported[clazz.to_s] ||=
        begin
          scope = scope_for(clazz)
          data = scope.to_a

          @broadcast.publish "fetch", clazz, data

          data
        rescue
          callback_failed_fetching_data clazz, $!, $@
        end
    end

    def callback_fetched_data model, data
      @on_fetch_data.inject(data) do |transformed_data, callback|
        instance_exec [model, transformed_data], callback
      end
    end

    def callback_failed_fetching_data( model, error, message)
      if @on_fetch_error
        @on_fetch_error.call(model, error, message)
      else
        fail "#{model} failed downloading with: #{error} \n #{message.join("\n")}"
      end
    end
  end
end
