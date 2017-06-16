module Export
  class Dump
    attr_reader :options, :exported

    def initialize(schema, &block)
      @schema = schema
      @options = {}
      @exported = {}
      instance_exec(&block) if block_given?
    end

    def table name, **options
      @options[name] = options
    end

    def all *tables
      tables.each do |table|
        @options[table] = :all
      end
    end

    def fetch
      @options.keys.map do |table|
        {table => fetch_data(table)}
      end.inject(&:merge)
    end

    def fetch_data table_name
      @exported[table_name] ||=
        begin
          sql = "select * from #{table_name.to_s}"
          if options = @options[table_name]
            if options.respond_to? :first
              key, value = options.first.to_a
              condition = options_for(key,value)
              puts condition if condition
              sql << " where #{condition}" if condition
            end
          end

          ActiveRecord::Base.connection.execute sql
        end
    end

    def options_for(key, value)
      if key == :where
        sql_condition_for(value)
      elsif key == :all
        # no conditions
      elsif key == :depends_on
        sql_condition_for(instance_exec(&value))
      else
        fail "what #{key} does? The value is: #{value}"
      end
    end

    def process
      File.open(@schema, 'w+') do |file|
        file.puts fetch
      end
    end

    def sql_condition_for(value)
      ActiveRecord::Base.__send__(:sanitize_sql, value)
    end

    def ids_for_exported(table)
      fetch_data(table).map{|e|e['id']}
    end
  end
end
