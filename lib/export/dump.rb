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
        on "fetch" do |table, data|
          puts "Fetched: #{table} with #{data&.length} records"
          data = Export.transform_data(table, data)
          publish "transform", table, data
        end

        on "transform" do |table, data|
          t = Time.now
          print "\n#{Time.now} #{table} - #{data.size}"
          filename = "tmp/#{table}.json"
          File.open(filename,"w+"){|f|f.puts data.to_json}
          print " finished #{filename} in #{Time.now - t} seconds. #{File.size(filename)}"
          publish "stored", filename
        end

        on "stored" do |filename|
          puts "add to zip: #{filename}"
        end
      end
    end

    def table name, &block
      @scope[name] = block
    end

    def all *tables
      tables.each do |table_name|
        table(table_name) { all }
      end
    end

    def ignore *table
      @ignore += [*table]
    end

    def fetch
      missing.each do |table|
        print "Fetching: #{table}"
        t = Time.now
        data = fetch_data(table)
        print " ... #{data&.length || 0} in #{Time.now - t} seconds\n"
      end
    end

    def missing
      self.class.convenient_order - @ignore - @exported.keys
    end

    def on_fetch_error(&block)
      @on_fetch_error = block
    end

    def fetch_data table_name
      @exported[table_name] ||=
        begin
          conditions = @scope[table_name] 
          scope = self.class.model(table_name).all

          if conditions
            file, line_number = conditions.source_location
            code = File.readlines(file)[line_number-1]
            print " with conditions: #{code}"
            scope = scope.instance_exec(&conditions)
          end

          if dependencies = self.class.dependencies[table_name]
            dependencies.each do |dependency|
              ids = ids_for_exported(dependency)
              unless ids.empty?
                scope = scope.where({ "#{dependency.singularize}_id" => ids })
                puts "#{scope.count} #{table_name} from #{ids.length} #{dependency}"
              end
            end
          end

          if dependencies = self.class.polymorphic_dependencies[table_name]
            dependencies.each do |polymorphic_association, tables|
              records = tables.inject({}){|h,t|h[t] = fetch_data(t) ; h}
              scope = scope.where(polymorphic_association => records.values.flatten)
              ids_from_each_table = records.map {|t,d| "#{d.size} #{t}" }.join(', ')
              puts " depending #{scope.count} #{table_name} from #{polymorphic_association} => #{ids_from_each_table}"
            end
          else
            print "#{scope.count} #{table_name}"
          end

          data = scope.to_a

          @broadcast.publish "fetch", table_name, data

          data
        rescue
          callback_failed_fetching_data table_name, $!, $@
        end
    end

    def callback_fetched_data table_name, data
      @on_fetch_data.inject(data) do |transformed_data, callback|
        instance_exec [table_name, transformed_data], callback #.call(table_name, transformed_data)
      end
    end

    def callback_failed_fetching_data( table_name, error, message)
      if @on_fetch_error
        @on_fetch_error.call(table_name, error, message)
      else
        fail "#{table_name} failed downloading with: #{error} \n #{message.join("\n")}"
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

    def ids_for_exported(table_name)
      return [] if @ignore.include?(table_name) # case a dependency look for this ignored table
      array = @exported[table_name]
      unless array
        print " ( depends #{table_name}"
        array = fetch_data(table_name)
        print " )"
        unless array
          @ignore << table_name
          puts "\n IGNORING #{table_name} since can't fetch records from it"
          array = []
        end
      end
      array.map(&:id)
    end

    def self.polymorphic_associates_with(original_table, polymorphic_model)
      (interesting_tables - [original_table]).select do |table|
        clazz = model(table)
        next unless clazz
        reflection = clazz.reflections[original_table]
        reflection && reflection.options[:as] == polymorphic_model
      end
    end

    def self.polymorphic_dependencies
      @polymorphic_dependencies ||=
        begin
          interesting_tables.inject({}) do |result, table|
            clazz = model(table)
            next unless clazz
            associations =
              clazz.reflections.select do |name, reflection|
                reflection.options && reflection.options[:polymorphic] == true
              end
            if associations.any?
              names = associations.values.map(&:name)
              polymorphic_map = names.inject({}) do |acc, name|
                assocs = polymorphic_associates_with(table, name)
                acc[name] = assocs if assocs.any?
                acc
              end
              result[table] = polymorphic_map
            end
            result
          end
        end
    end

    def self.dependencies
      @dependencies ||=
        interesting_tables.inject({}) do |acc, t|
          model = model(t)
          if model
            references = model.reflections.select { |_, v| v.macro == :belongs_to && !v.options.key?(:polymorphic) }
            acc[t] = references.values.map(&:plural_name) unless references.empty?
          end
          acc
        end
    end

    def self.independents
      (dependencies.values.flatten - dependencies.keys).uniq
    end

    def self.model(table_name)
      const = table_name.to_s.classify.safe_constantize
      return const if const && const < ActiveRecord::Base
      Class.new(ActiveRecord::Base) { self.table_name = table_name }
    end

    def self.interesting_tables
      @interesting_tables ||= 
        ActiveRecord::Base.connection.tables -
          %w[schema_migrations ar_internal_metadata]
    end

    def self.convenient_order
      (independents | dependencies.keys | polymorphic_dependencies.keys)
    end
  end
end
