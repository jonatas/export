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
      fetch_order.map(&method(:fetch_data))
    end

    def fetch_data table_name
      sql = "select * from #{table_name.to_s}"
      if options = @options[table_name]
        if options.respond_to? :first
          key, value = options.first.to_a
          condition = options_for(key,value)
          sql << " where #{condition}" if condition
        end
      end

      data = ActiveRecord::Base.connection.execute sql
      if has_dependents?(table_name)
        @exported[table_name] = data.map{|e|e['id']}
      end
      data
    end

    def options_for(key, value)
      if key == :where
        sql_condition_for(value)
      elsif key == :all
        # no conditions
      elsif key == :depends_on
        "#{value.to_s.singularize}_id in (#{exported_ids_for(value).join(',')})"
      else
        fail "what #{key} does? The value is: #{value}"
      end
    end

    def process
      File.open(@schema, 'w+') do |file|
        file.puts data_to_export
      end
    end

    def data_to_export

    end

    def sql_condition_for(value)
      ActiveRecord::Base.__send__(:sanitize_sql, value)
    end

    def exported_ids_for(table)
      @exported[table] || []
    end

    def has_dependents? table
      @options.values.grep(Hash).any?{|v| v[:depends_on] && v[:depends_on] == table}
    end

    def fetch_order
      @options.keys.sort_by{|k|has_dependents?(k) ? 0 : 1}
    end
  end
end
