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
          end
          if dependencies = self.class.polymorphic_dependencies[table_name]
            dependencies.each do |polymorphic_association, tables|
              scope = scope.where(polymorphic_association => tables.flat_map{|t|fetch_data(t)})
              puts "#{scope.count} #{table_name} from #{polymorphic_association} => #{tables.map{|t| "#{fetch_data(t)&.length} #{t}"}}"
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
          interesting_tables.map do |table|
            clazz = table.classify.safe_constantize
            next unless clazz
            associations =
              clazz.reflections.select do |name, reflection|
                reflection.options && reflection.options[:polymorphic] == true
              end
            if associations.any?
              names = associations.values.map(&:name)
              polymorphic_map = names.map{|name| {name => polymorphic_associates_with(table, name) } }.flatten
              { table => polymorphic_map.inject(&:merge!) }
            end
          end.compact.inject(:merge!)
        end
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
      table_name.to_s.classify.safe_constantize ||
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
