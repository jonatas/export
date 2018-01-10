module Export
  # Represents a dependency between models
  class Dependency
    # @return [String] the name of the dependency.
    delegate :name, to: :@reflection

    # @return [String] the column for the `id` of the dependency.
    delegate :foreign_key, to: :@reflection

    # Gives the models of a given dependency. If the model is polymorphic,
    # returns all the models used in database. If not, returns only the
    # declared model from the reflection.
    #
    # @return [Model] the models of the dependency.
    attr_reader :models

    # Creates a new dependency based on an `ActiveRecord` reflection.
    #
    # @param reflection [ActiveRecord::Reflection::BelongsToReflection]
    #        the reflection.
    # @param dump [Dump] the dump to be used.
    # @return [Dependency] the dependency created.
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

    # Informs if the dependency is polymorphic.
    #
    # @return [Boolean] true if it is polymorphic.
    def polymorphic?
      @reflection.polymorphic? == true
    end

    # Informs the column name for the `type` in polymorphic dependencies.
    #
    # @return [String] the column name or `nil` if not polymorphic.
    def foreign_type
      @reflection.foreign_type if polymorphic?
    end

    # Informs if the dependency is optional. This consider columns that allow
    # nil values or default to zero. It is the opposite of #hard?.
    #
    # @return [Boolean] true if it is optional.
    def soft?
      column = @reflection.active_record.column_for_attribute(@reflection.foreign_key)

      column.null == true || column.default.to_s == '0'
    end

    # Informs if the dependency is required. This consider columns that do
    # not allow nil values and do not default to zero. It is the opposite of
    # #soft?.
    #
    # @return [Boolean] true if it is required.
    def hard?
      !soft?
    end
  end
end
