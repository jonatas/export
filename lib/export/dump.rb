module Export
  class Dump
    attr_reader :options, :exported

    def initialize(schema, &block)
      @schema = schema
      @scope = {}
      @exported = {}
      @on_fetch_data = [ Export.method(:transform_data) ]
      @ignore = []
      instance_exec(&block) if block_given?
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
      (self.class.convenient_order - @ignore).map do |table|
        print "fetching: #{table}"
        t = Time.now
        data = fetch_data(table) || []
        print " ... #{data ? data.length : "no data"} in #{Time.now - t} seconds\n"
        {table => data}
      end.inject(&:merge)
    end

    def on_fetch_data(&block)
      @on_fetch_data << block
    end

    def on_fetch_error(&block)
      @on_fetch_error = block
    end

    def fetch_data table_name
      @exported[table_name] ||=
        begin
          conditions = @scope[table_name] 
          scope = self.class.model(table_name)
          if conditions
            scope = scope.instance_exec(&conditions)
          else
            scope = scope.all
          end
          if dependency = self.class.dependencies[table_name]
            ids = ids_for_exported(dependency)
            unless ids.empty?
              scope = scope.where({ "#{dependency.singularize}_id" => ids })
              puts "#{scope.count} #{table_name} from #{ids.length} #{dependency}"
            end
          else
            puts "#{scope.count} #{table_name}"
          end
          callback_fetched_data table_name, scope.to_a
        rescue
          callback_failed_fetching_data table_name, $!, $@
        end
    end

    def callback_fetched_data table_name, data
      @on_fetch_data.inject([]) do |transformed_data, callback|
       callback.call(table_name, transformed_data.empty? ? data : transformed_data) || data
      end
    end

    def callback_failed_fetching_data( table_name, error, message)
      @on_fetch_error.call(table_name, error, message)
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

    def self.dependencies
      @dependencies ||=
        begin
          dependencies = {}
          tables = interesting_tables
          tables.each do |t|
            foreign = "#{t.singularize}_id"
            references = tables.select{|m| t!=m && model(m).column_names.include?(foreign)}
            unless references.empty?
              references.each do |r|
                dependencies[r] = t # references
              end
            end
          end
          dependencies
        end
    end

    def self.independents
      dependencies.values - dependencies.keys
    end

    def self.model(table_name)
      Class.new(ActiveRecord::Base) do
        self.table_name = table_name
      end
    end

    def self.interesting_tables
      @interesting_tables ||= 
        ActiveRecord::Base.connection.tables -
          %w[schema_migrations ar_internal_metadata]
    end

    def self.convenient_order
      (independents | dependencies.keys)
    end
  end
end
