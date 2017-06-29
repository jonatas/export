require 'export/broadcast'

module Export
  class Dump
    attr_reader :options, :exported, :broadcast

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
          data = Export.transform_data(model, data)
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
      missing.each do |model|
        print "Fetching: #{model}"
        t = Time.now
        data = fetch_data(model)
        print " ... #{data&.length || 0} in #{Time.now - t} seconds\n"
      end
    end

    def missing
      self.class.convenient_order - @ignore - @exported.keys
    end

    def on_fetch_error(&block)
      @on_fetch_error = block
    end

    def fetch_data clazz
      @exported[clazz.to_s] ||=
        begin
          scope = clazz.all
          conditions = @scope[clazz.to_s]

          if conditions
            file, line_number = conditions.source_location
            code = File.readlines(file)[line_number-1]
            print ">> #{clazz}: with conditions  #{code}"
            scope = scope.instance_exec(&conditions)
          else
            print ">> #{clazz} :: #{clazz.class}: without conditions #{@scope.keys} <<<<<<<<<<< "
          end

          if dependencies = self.class.dependencies[clazz]
            dependencies.each do |column_name, dependency|
              ids = ids_for_exported(dependency.klass)
              unless ids.empty?
                scope = scope.where(dependency.foreign_key => ids)
                puts "#{scope.count} #{clazz} from #{ids.length} #{dependency}"
              end
            end
          end

          if dependencies = self.class.polymorphic_dependencies[clazz]
            dependencies.each do |polymorphic_association, associations|
              records = associations.inject({}){|h,c|h[c] = fetch_data(c) ; h}
              puts "scope = scope.where(#{polymorphic_association} => #{records.values.flatten})"
              scope = scope.where(polymorphic_association => records.values.flatten)
              ids_from_models = records.map {|t,d| "#{d.size} #{t}" }.join(', ')
              puts " depending #{scope.count} #{clazz} from #{polymorphic_association} => #{ids_from_models}"
            end
          else
            print "#{scope.count} #{clazz}"
          end

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

    def sql_condition_for(value)
      ActiveRecord::Base.__send__(:sanitize_sql, value)
    end

    def ids_for_exported(model)
      return [] if @ignore.include?(model) # case a dependency look for this ignored table
      array = @exported[model]
      unless array
        print " ( depends #{model}"
        array = fetch_data(model)
        print " )"
        unless array
          @ignore << model
          puts "\n IGNORING #{model} since can't fetch records from it"
          array = []
        end
      end
      array.map(&:id)
    end

    def self.polymorphic_associates_with(original_model, polymorphic_model)
      (interesting_models - [original_model]).select do |clazz|
        reflection = clazz.reflections[original_model.table_name]
        reflection && reflection.options[:as] == polymorphic_model
      end
    end

    def self.polymorphic_dependencies
      @polymorphic_dependencies ||=
        begin
          interesting_models.inject({}) do |result, model|
            deps = polymorphic_dependencies_of(model)
            result[model] = deps if deps && deps.any?
            result
          end
        end
    end

    def self.polymorphic_dependencies_of(model)
      associations =
        model.reflections.select do |name, reflection|
          reflection.options && reflection.options[:polymorphic] == true
        end
      if associations.any?
        names = associations.values.map(&:name)
        names.inject({}) do |acc, name|
          assocs = polymorphic_associates_with(model, name)
          acc[name] = assocs if assocs.any?
          acc
        end
      end
    end

    def self.dependencies
      @dependencies ||=
        interesting_models.inject({}) do |acc, model|
          deps = dependencies_of(model)
          acc[model] = deps if deps && deps.any?
          acc
        end
    end

    def self.dependencies_of(model)
      model.reflections.select { |_, v| v.macro == :belongs_to && !v.options.key?(:polymorphic) }
    end

    def self.independents
       interesting_models -
         dependencies_from_reflections -
         dependencies.keys -
         polymorphic_dependencies.keys
    end

    def self.dependencies_from_reflections
      dependencies.values.inject(&:merge).values.map(&:active_record) 
    end

    def self.interesting_models
      @interesting_models ||=
        begin
          ActiveRecord::Base.descendants
        end
    end

    def self.convenient_order
      (independents | dependencies.keys | polymorphic_dependencies.keys)
    end
  end
end
