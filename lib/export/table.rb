module Export
  class Table

    attr_accessor :name
    attr_reader :replacements

    def initialize(name:)
      self.name = name
      @replacements = {}
      Export.replacements[name] = self
    end

    def replace(info, with_value)
      @replacements[info] ||= []
      @replacements[info] << with_value
    end

    def ignore(*columns)
      columns.each do |column|
        replace(column, nil)
      end
    end
  end
end
