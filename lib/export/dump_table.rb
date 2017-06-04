module Export
  class DumpTable
    attr_reader :table
    def initialize(table)
      @table = table
    end

    def process(data)
      new_data = data.map do |record|
        apply_replacements!(record)
      end
      new_data
    end

    private

    def apply_replacements!(record)
      table.replacements.each do |field, modifiers|
        modifiers.each do |modifier|
          value = modifier && value_from(modifier, record)
          record.public_send("#{field}=", value)
        end
      end
      record
    end

    def value_from(modifier, record)
      return modifier if modifier.is_a?(String)
      if modifier.arity.zero?
        modifier.call
      else
        modifier.call(record)
      end
    end
  end
end
