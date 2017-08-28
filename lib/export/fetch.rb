
module Export
  class Fetch
    attr_reader :dependencies, :additional_scope, :model
    def initialize(dependency_tree, additional_scope)
      @model = dependency_tree.model
      @dependencies = dependency_tree.dependencies.values
      @additional_scope = additional_scope
    end

    def scope
      return @scope if defined? @scope
      initialize_scope
      add_regular_dependencies
      add_polymorphic_dependencies
      @scope
    end

    def initialize_scope
      @scope =
        if scope = additional_scope[model.to_s]
          model.instance_exec(&scope)
        else
          model.all
        end
    end

    def add_regular_dependencies
      (dependencies - polymorphic_dependencies).each do |dep|
        if has_additional_scope?
          query = dep.fetch(additional_scope)
          if query != dep.model.all
            @scope = @scope.where(dep.name => query)
          end
        end
      end
    end

    def add_polymorphic_dependencies
      return if polymorphic_dependencies.none?{|dep|dep.has_additional_scope?(additional_scope)}
      current_scope = @scope.dup
      polymorphic_dependencies.each_with_index do |dep, i|
        condition = current_scope.where(dep.name => dep.fetch(additional_scope))
        if i == 0
          @scope = condition
        else
          @scope = @scope.union condition
        end
      end
    end

    def polymorphic_dependencies
      dependencies.select(&:polymorphic?)
    end

    def has_additional_scope?(additional_scope=@additional_scope)
      additional_scope.has_key?(@model.to_s) ||
        @dependencies.any?{|dep|dep.has_additional_scope?(additional_scope)}
    end

  end
end
