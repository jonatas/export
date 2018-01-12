module Export
  # Represents a column that can be exported
  class Column
    # The default replacements that can be used whenever someone ask for
    # replace a given column without specifing the replacement.
    DEFAULT_REPLACEMENTS = {
      /email/ => ->(email) { email.sub('@', '+') + '@example.com' },
      /password$/ => 'password',
      /name/ => FFaker::Name.name
    }.with_indifferent_access

    # @return [String] the name of the column.
    attr_reader :name

    # @return [Column] the Active Record, if defined.
    attr_reader :raw_column

    # Creates a column.
    #
    # @param column can be either a String, Symbol or Active Record column.
    # @param dump [Dump] a dump to be used with. If provided, the column
    #                    is going to use the dump information as the default
    #                    behaviour.
    # @return [Column] the column.
    def initialize(column, dump = nil)
      if column.respond_to?(:name)
        @name = column.name
        @raw_column = column
      else
        @name = column
      end

      @dump = dump
      @ignore = false
    end

    # Allows the configuration of the column using a DSL-like approach.
    #
    # @param block the block to be called.
    def config(&block)
      instance_exec(&block)
    end

    # Checks if the column should be ignored and takes into account if the
    # column should be globally ignored, when it is possible.
    #
    # @return [Boolean] wheter or not the column should be ignored.
    def ignore?
      @ignore || (dump_column&.ignore? == true)
    end

    # Allows defining that the column should be ignored completely from dump.
    #
    # @param value [Boolean] the ignore value.
    def ignore(value = true)
      @ignore = value
    end

    # Allows defining a replacement strategy for the given column.
    #
    # @param replacement the object to be used to perform the replacement.
    #                    If a block, Proc or lambda is provided, the object
    #                    is going to be called. If not, the object is going
    #                    to be used. If nothing is provided, a default
    #                    replacement is going to be searched for the column
    #                    name.
    def replace_with(replacement = nil, &block)
      raise ArgumentError, 'Cannot replace with both data and block' if replacement && block

      @replacement = replacement || block || default_replacement
    end
    alias replace replace_with

    # Simple syntax sugar for replacing the content with `nil`.
    def nullify
      replace_with { nil }
    end

    # Replace the given value based on the replace strategy defined in
    # #replace_with. If no replacement is explicity defined and a dump
    # were provided for the column, a replacement will be searched in dump.
    # If nothing can be found, the value is returned.
    #
    # @param value the value to be replaced.
    # @return the replaced value or the value.
    def replace_value(value)
      replacement = @replacement || dump_column&.replacement
      return value unless replacement

      replacement.respond_to?(:call) ? replacement.call(value) : replacement
    end

    protected

    attr_reader :replacement

    private

    def dump_column
      column = @dump.columns[@name] if @dump
      column = nil if column&.equal?(self)
      column
    end

    def default_replacement
      DEFAULT_REPLACEMENTS.find { |r, _| @name.match?(r) }&.last
    end
  end
end
