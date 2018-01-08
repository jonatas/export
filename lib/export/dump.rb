require 'export/broadcast'

module Export
  # Represents the dump process
  class Dump
    DEFAULT_SCHEMA = 'dump'.freeze

    # attr_reader :options, :exported, :broadcast, :scope

    def initialize(schema = DEFAULT_SCHEMA, &block)
      @schema = schema
      @models = {}
      # @exported = {}
      # @exporting = {}
      # @ignore = []
      # @queue = Queue.new
      # @broadcast = setup_broadcast
      config(&block) if block_given?
    end

    def config(&block)
      instance_exec(&block)
    end

    def model_for(clazz, &block)
      model = @models[clazz]
      unless model
        model = Model.new(clazz)
        @models[clazz] = model

        model.load(self)
      end

      model.config(&block) if block_given?

      model
    end
    alias model model_for

    def reload_models
      @models.values.each(&:reload)
    end

    def scope(clazz, &block)
      model_for(clazz).scope_by(&block)
    end

    # def setup_broadcast
    #   Broadcast.new do
    #     on 'fetch' do |model, data|
    #       puts "Fetched: #{model} with #{data&.length} records"
    #       if Export.replacements_for(model)
    #         print ' > Transforming...'
    #         t = Time.now
    #         data = Export.transform_data(model, data)
    #         print " done in #{Time.now - t} seconds"
    #       end
    #       publish 'transform', model, data
    #     end

    #     on 'transform' do |model, data|
    #       t = Time.now
    #       print "\n#{Time.now} #{model} - #{data.size}"
    #       Dir.mkdir('tmp') unless Dir.exist?('tmp')
    #       filename = "tmp/#{model.name.underscore.tr('/', '__')}.json"
    #       File.open(filename, 'w+') { |f| f.puts data.to_json }
    #       print " finished #{filename} in #{Time.now - t} seconds. #{File.size(filename)}"
    #       publish 'stored', filename
    #     end

    #     on 'stored' do |filename|
    #       puts "add to zip: #{filename}"
    #     end
    #   end
    # end

    # def ignore(*model)
    #   @ignore += [*model]
    # end

    # def fetch
    #   Export::Model.interesting_models.each do |model|
    #     print "Fetching: #{model}"
    #     t = Time.now
    #     data = fetch_data(model)
    #     print " ... #{data&.length || 0} in #{Time.now - t} seconds\n"
    #   end
    # end

    # def on_fetch_error(&block)
    #   @on_fetch_error = block
    # end

    # def scope_for(clazz)
    #   Export::Model.new(clazz, self).scope
    # end

    # def fetch_data(clazz)
    #   @exported[clazz.to_s] ||=
    #     begin
    #       scope = scope_for(clazz)
    #       data = scope.to_a

    #       @broadcast.publish 'fetch', clazz, data

    #       data
    #     rescue
    #       callback_failed_fetching_data clazz, $ERROR_INFO, $ERROR_POSITION
    #     end
    # end

    # def callback_fetched_data(model, data)
    #   @on_fetch_data.inject(data) do |transformed_data, callback|
    #     instance_exec [model, transformed_data], callback
    #   end
    # end

    # def callback_failed_fetching_data(model, error, message)
    #   raise "#{model} failed downloading with: #{error} \n #{message.join("\n")}" unless @on_fetch_error

    #   @on_fetch_error.call(model, error, message)
    # end

    # def process
    #   filename = @schema.tr(' ', '_').downcase + '.json'
    #   puts "Writing: #{filename}"
    #   File.open(filename, 'w+') do |file|
    #     file.puts fetch.to_json
    #   end
    #   puts "Finished. #{fetch.values.map(&:size).inject(:+)} records saved"
    # end
  end
end
