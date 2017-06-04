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

    def options_for(key, value)
      if key == :where
        " where #{sql_condition_for(value)}"
      elsif key == :all
        # no conditions
      elsif key == :depends_on
        "#{value.to_s.singularize}_id in (#{exported_ids_for(value).join(',')})"
      else
        fail "what #{key} does? The value is: #{value}"
      end
    end
    def process
      @schema.map do |table, data|

        table.process(data)
      end
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
  end
end
