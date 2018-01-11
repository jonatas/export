module Export
  # Represents the dump process
  class Dump
    # Creates a dump.
    #
    # @param block the block to be called.
    # @return [Dump] the new dump.
    def initialize(&block)
      @models = {}

      config(&block) if block_given?
    end

    # Allows the configuration of the dump using a DSL-like approach.
    #
    # @param block the block to be called.
    def config(&block)
      instance_exec(&block)
    end

    # Returns the model for a given class. If the model does not exists,
    # it is created and prepared to be used. If a block is given, the
    # block is called in the context of the model, so it is possible
    # to configure it.
    #
    # @param clazz [Class] the class of the model.
    # @param block the block to be called.
    def model_for(clazz, &block)
      model = @models[clazz]
      unless model
        model = Model.new(clazz)
        @models[clazz] = model

        model.load(self)
      end

      model.config(&block) if block_given?

      model
    end
    alias model model_for

    # All valid models the inherit from `ActiveRecord::Base`.
    #
    # @return [Array] the models.
    def all_models
      ActiveRecord::Base.descendants.reject(&:abstract_class).select(&:table_exists?).map { |c| model(c) }
    end

    # Reloads the internal state of each loaded model.
    def reload_models
      @models.values.each(&:reload)
    end

    # Simple syntax sugar for scoping a model.
    #
    # @param clazz [Class] the class of the model.
    # @param block the block to be called.
    def scope(clazz, &block)
      model_for(clazz).scope_by(&block)
    end
  end
end
