module Export
  # Represents a dependency between models
  class Dependency
    delegate :name, :foreign_key, :foreign_type, to: :@reflection

    attr_reader :models

    def polymorphic?
      @reflection.polymorphic? == true
    end

    def foreign_type
      @reflection.foreign_type if polymorphic?
    end

    def soft?
      column = @reflection.active_record.column_for_attribute(@reflection.foreign_key)

      column.null == true || column.default.to_s == '0'
    end

    def hard?
      !soft?
    end

    private

    def initialize(reflection, dump)
      @reflection = reflection
      @dump = dump

      klasses = if reflection.polymorphic?
                  reflection.active_record.distinct.pluck(reflection.foreign_type).map(&:safe_constantize)
                else
                  [reflection.klass]
                end
      @models = klasses.map { |k| @dump.model_for(k) }
    end
  end
end
