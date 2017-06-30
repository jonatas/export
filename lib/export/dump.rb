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
          filename = "tmp/#{model.name.underscore}.json"
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

    def fetch
      self.class.interesting_models.each do |model|
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
      Export::Model.new(clazz, self).scope
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

    def process
      filename = @schema.tr(' ','_').downcase + '.json'
      puts "Writing: #{filename}"
      File.open(filename, 'w+') do |file|
        file.puts fetch.to_json
      end
      puts "Finished. #{fetch.values.map(&:size).inject(:+)} records saved"
    end

    def self.interesting_models
      @interesting_models ||=
        begin
          ActiveRecord::Base.descendants
        end
    end
  end
end
