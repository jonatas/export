module Export
  class TransformData
    attr_reader :table
    def initialize(table)
      @table = table
    end

    def process(data)
      data.map do |record|
        apply_replacements!(record)
      end
    end

    private

    def apply_replacements!(record)
      Export.replacements_for(@table).each do |field, modifiers|
        next if record.public_send(field).nil?
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
