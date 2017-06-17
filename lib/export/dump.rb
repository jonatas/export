module Export
  class Dump
    attr_reader :options, :exported

    def initialize(schema, &block)
      @schema = schema
      @options = {}
      @exported = {}
      @on_fetch_data = [ Export.method(:transform_data) ]
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

    def model(table_name)
      Class.new(ActiveRecord::Base) do
        self.table_name = table_name
      end
    end

    def on_fetch_data(block)
      @on_fetch_data << block
    end

    def fetch_data table_name
      @exported[table_name] ||=
        begin
          scope = model(table_name).all
          if options = @options[table_name]
            if options.respond_to? :first
              condition = options_for(*options.first.to_a)
              scope = scope.where(condition)
            end
          end
          callback_fetched_data table_name, scope.to_a
        end
    end

    def callback_fetched_data table_name, data
      @on_fetch_data.inject([]) do |transformed_data, callback|
       callback.call(table_name, transformed_data.empty? ? data : transformed_data) || data
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
      filename = @schema.tr(' ','_').downcase + '.json'
      puts "Writing: #{filename}"
      File.open(filename, 'w+') do |file|
        file.puts fetch
      end
      puts "Finished. #{fetch.values.map(&:size).inject(:+)} records saved"
    end

    def sql_condition_for(value)
      ActiveRecord::Base.__send__(:sanitize_sql, value)
    end

    def ids_for_exported(table)
      fetch_data(table).map(&:id)
    end
  end
end
