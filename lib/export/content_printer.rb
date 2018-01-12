module Export
  # Represents a printer that prints the content of a dump as INSERTs.
  class ContentPrinter
    # Creates a content printer.
    #
    # @param dump [Dump] the dump to be used.
    # @param io [IO] the IO to be printed into.
    # @param batch_size [Integer] the ammount of records that should be
    #                             injected in a single INSERT command.
    # @return [ContentPrinter] the new printer.
    def initialize(dump, io, batch_size: 500)
      @dump = dump
      @io = io
      @batch_size = batch_size
    end

    # Prints the content of non-ignored models from the dump into the given IO.
    #
    # @return [IO] the io.
    def print
      @dump.models.each do |model|
        print_model model unless model.ignore?
      end

      @io
    end

    private

    def print_model(model)
      count = 0
      model.scope.execute_in_batches size: @batch_size do |row|
        if (count % @batch_size).zero?
          print_footer unless count.zero?
          print_header model
        else
          @io.puts ','
        end

        print_model_row model, row
        count += 1
      end

      print_footer unless count.zero?
    end

    def print_header(model)
      columns = model.enabled_columns

      @io.puts "INSERT INTO #{model.clazz.table_name} (#{columns.keys.join(', ')}) VALUES ("
    end

    def print_model_row(model, row)
      connection = ActiveRecord::Base.connection
      columns = model.enabled_columns.map { |n, c| [n, c.raw_column] }.to_h
      values = row.map do |column, value|
        value = model.columns[column].replace_value value

        connection.quote(connection.type_cast(value, columns[column]))
      end

      @io.print "  (#{values.join(', ')})"
    end

    def print_footer
      @io.puts "\n);"
    end
  end
end
