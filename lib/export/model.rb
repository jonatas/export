module Export
  # Represents a model to be exported and its structure
  class Model
    CircularDependencyPathItem = Struct.new(:parent, :dependency, :model)
    DependencyTable = Struct.new(:dependency, :table)

    DEPENDENCY_SEPARATOR = '•'.freeze
    SOFT_PREFIX = 'soft_'.freeze
    HARD_PREFIX = 'hard_'.freeze

    # @return [Class] the class on which this model represent.
    attr_reader :clazz

    # Creates a model for a given `ActiveRecord` clazz.
    #
    # @param clazz [Class] the `ActiveRecord` class.
    # @return [Model] the new model.
    def initialize(clazz)
      @clazz = clazz
      @ignore = false
    end

    # Returns a simple representantion of the model.
    #
    # @return [String] the string representation.
    def inspect
      "#<#{self.class.name} @clazz=#{@clazz.name}>"
    end

    # Performs the loading process of the model
    #
    # @param dump [Dump] the dump to be used.
    # @raise if was already loaded.
    def load(dump)
      raise 'Cannot reload a model from a new dump.' if defined?(@dump)

      @dump = dump
      @dependencies = @clazz.reflections.map do |_, reflection|
        next unless reflection.is_a?(ActiveRecord::Reflection::BelongsToReflection)

        Dependency.new(reflection, @dump)
      end.compact
    end

    # Reloads the internal state.
    def reload
      @circular_dependencies = nil
      @hard_scope = nil
      @scope = nil

      @dependencies = @clazz.reflections.map do |_, reflection|
        next unless reflection.is_a?(ActiveRecord::Reflection::BelongsToReflection)

        dependency = @dependencies.find { |d| d.reflection == reflection }
        if dependency
          dependency.reload
          dependency
        else
          Dependency.new(reflection, @dump)
        end
      end.compact
    end

    # Allows the configuration of the model using a DSL-like approach.
    #
    # @param block the block to be called.
    def config(&block)
      instance_exec(&block)
    end

    # Allows the definition of a scope to limit the query using `ActiveRecord`
    # syntax.
    #
    # @param block the block to be called.
    # @raise if #scope had already been called, because you can change it after
    #        this. You can always reload and try again.
    def scope_by(&block)
      raise 'Cannot define scope after scope has been called.' if @scope

      @scope_block = block
    end

    # Allows dependencies to be ignored in scoping process. The dependencies
    # are just ignored, like if those columns were just data columns.
    #
    # @param clazz [Symbol] the names of the dependencies.
    def ignore_dependency(*args)
      raise 'Cannot ignore dependencies without loading.' unless @dump

      args.each do |name|
        @dependencies.find { |d| d.name == name }.ignore
      end
    end
    alias ignore_dependencies ignore_dependency

    # @return [Boolean] wheter or not the model should be ignored.
    def ignore?
      @ignore
    end

    # Allows defining that the model should be ignored completely from dump.
    #
    # @param value [Boolean] the ignore value.
    def ignore(value = true)
      @ignore = value
    end

    # Informs if a model should be scoped or not. This checks if somebody
    # restricted the model using #scoped_by or if any of the dependencies
    # is scoped, recursively.
    #
    # @param block the block to be called.
    def scoped?
      @scope_block.present? || enabled_dependencies.any? { |d| dependency_scoped?(d) }
    end

    # Gives all dependencies of a model that are not explicitly ignored.
    #
    # @return [Array] the enabled depencies
    def enabled_dependencies
      @dependencies.reject(&:ignore?)
    end

    # Gives a query that scopes the model by the definition (#scope_by) and
    # by it's hard and soft dependencies.
    # When soft dependencies are circular, the columns (`id` and `type`, when
    # polymorphic) of each dependency are restricted to the presence of the
    # dependent model. This means that a record A that weakly references a
    # model B, can result in a scope where the reference of record B inside
    # model A will be faked to `null` if model B is not scoped.
    # When soft dependencies are not circular or dependencies are hard, the
    # model is restricted using a simple `WHERE ... IN (SELECT id ...)`
    # statement.
    #
    # @return [Statement] the statement that scopes the model.
    def scope
      return @scope if @scope

      @scope = hard_scope.dup
      soft_dependencies = []

      enabled_dependencies.each do |dependency|
        binds = nil
        node = nil

        if dependency.polymorphic?
          alias_prefix = SOFT_PREFIX if @scope.manager.ast.with&.children&.map(&:left)&.map(&:name)&.include?("#{HARD_PREFIX}#{dependency.name.to_s.pluralize}")
          dependency.models.each do |model|
            next unless model.scoped?
            next unless circular_dependency?(dependency, model) || alias_prefix

            model_manager = model.hard_scope.manager.dup
            model_manager.projections = [
              Arel::Nodes::As.new(Arel::Nodes::Quoted.new(model.clazz.name), Arel::Nodes::SqlLiteral.new(:type.to_s)),
              model.primary_key.as(:id.to_s)
            ]

            if node
              binds.concat(model.hard_scope.binds)
              node = node.union_all(model_manager)
            else
              binds = model.hard_scope.binds
              node = model_manager.ast
            end
          end
        else
          next unless circular_dependency?(dependency) && dependency.soft?
          next unless dependency.models.first.scoped?

          model = dependency.models.first
          binds = model.hard_scope.binds
          manager = model.hard_scope.manager.dup
          manager.projections = [model.primary_key.as(:id.to_s)]
          node = manager.ast
        end

        next unless node

        dependencies = Arel::Table.new("#{alias_prefix}#{dependency.name.to_s.pluralize}")

        on = dependencies[:id].eq(arel_table[dependency.foreign_key])
        on = dependencies[:type].eq(arel_table[dependency.foreign_type]).and(on) if dependency.polymorphic?

        @scope.manager
              .join(dependencies, Arel::Nodes::OuterJoin)
              .on(on)
              .prepend_with(Arel::Nodes::As.new(dependencies, Arel::Nodes::Grouping.new(node)))
        @scope.binds.unshift(*binds)
        soft_dependencies << DependencyTable.new(dependency, dependencies)
      end

      unless soft_dependencies.empty?
        @scope.manager.projections = @clazz.column_names.map do |column|
          info = soft_dependencies.find { |dt| dt.dependency.foreign_key == column }
          next info.table[info.dependency.models.first.clazz.primary_key].as(info.dependency.foreign_key) if info

          info = soft_dependencies.find { |dt| dt.dependency.foreign_type == column }
          next info.table[:type].as(info.dependency.foreign_type) if info

          arel_table[column]
        end
      end

      @scope
    end

    # The number of lines of the model in its unscoped state. A simple
    # `SELECT COUNT(*) FROM ...`.
    #
    # @return [Integer] the number of lines.
    def full_count
      @clazz.count
    end

    # The number of scoped items.
    #
    # @return [Integer] the number of lines.
    def scope_count
      count_scope = scope.dup
      count_scope.manager.projections = [Arel.star.count]

      count_scope.execute.first&.values&.first || 0
    end

    # The scoped percentual, that is, the number of scoped lines divided
    # by the total number of lines of the model.
    #
    # @return [Float] the percentual or `nil` if #full_count is empty.
    def scope_percentual
      total = full_count
      scope_count / total.to_f if total.positive?
    end

    protected

    delegate :arel_table, to: :clazz

    def hard_scope
      return @hard_scope if @hard_scope

      relation = @scope_block ? @clazz.instance_exec(&@scope_block) : @clazz.all
      @hard_scope = Statement.from_relation(relation)

      enabled_dependencies.each do |dependency|
        if dependency.polymorphic?
          binds = nil
          node = nil

          dependency.models.each do |model|
            next unless model.scoped?
            if circular_dependency?(dependency, model)
              next if dependency.soft?

              raise CircularDependencyError, "Scoped circular dependency detected in #{@clazz.name}##{dependency.name}."
            end

            model_manager = model.hard_scope.manager.dup
            model_manager.projections = [
              Arel::Nodes::As.new(Arel::Nodes::Quoted.new(model.clazz.name), Arel::Nodes::SqlLiteral.new('type')),
              model_manager.source.left[:id].as('id')
            ]

            if node
              binds.concat(model.hard_scope.binds)
              node = node.union_all(model_manager)
            else
              binds = model.hard_scope.binds
              node = model_manager.ast
            end
          end

          if node
            alias_prefix = HARD_PREFIX if dependency.models.any? { |m| m.scoped? && circular_dependency?(dependency, m) && dependency.soft? }
            manager_alias = Arel::Table.new("#{alias_prefix}#{dependency.name.to_s.pluralize}").from
            manager_alias.projections = [
              manager_alias.source.left[:type],
              manager_alias.source.left[:id]
            ]

            @hard_scope.binds.unshift(*binds)
            @hard_scope.manager
                       .where(Arel::Nodes::Grouping.new([arel_table[dependency.foreign_type], arel_table[dependency.foreign_key]]).in(manager_alias))
                       .prepend_with(Arel::Nodes::As.new(manager_alias.source.left, Arel::Nodes::Grouping.new(node)))
          end
        else
          next unless dependency_scoped?(dependency)

          model = dependency.models.first
          manager = model.hard_scope.manager.dup
          manager.projections = [model.primary_key]

          @hard_scope.manager.where(arel_table[dependency.foreign_key].in(manager))
          @hard_scope.binds.concat(model.hard_scope.binds)
        end
      end

      @hard_scope
    end

    def primary_key
      arel_table[@clazz.primary_key]
    end

    private

    private_constant :CircularDependencyPathItem
    private_constant :DependencyTable
    private_constant :DEPENDENCY_SEPARATOR
    private_constant :SOFT_PREFIX
    private_constant :HARD_PREFIX

    def circular_dependencies
      unless @circular_dependencies
        @circular_dependencies = []

        block = proc do |parent, dependency, path = []|
          dependency.models.each do |model|
            path << CircularDependencyPathItem.new(parent, dependency, model)

            if model == self
              raise CircularDependencyError, "Circular dependency detected in #{self.clazz.name}##{path.first.dependency.name}." unless path.first.dependency.polymorphic? || path.any? { |i| i.dependency.soft? }

              name = path.first.dependency.name
              name = name.to_s + DEPENDENCY_SEPARATOR + path.first.model.clazz.name if path.first.dependency.polymorphic?

              @circular_dependencies << name
            elsif path.count(path.last) == 1
              model.enabled_dependencies.each { |d| block.call model, d, path.dup }
            end
          end
        end

        enabled_dependencies.each { |d| block.call self, d }
      end

      @circular_dependencies
    end

    def dependency_scoped?(dependency, model = nil)
      return false if circular_dependency?(dependency, model) && (dependency.soft? || dependency.polymorphic?)

      models = model ? [model] : dependency.models
      models.any?(&:scoped?)
    end

    def circular_dependency?(dependency, model = nil)
      if dependency.polymorphic?
        models = model ? [model] : dependency.models
        return true if models.any? do |dependency_model|
          circular_dependencies.include?(dependency.name.to_s + DEPENDENCY_SEPARATOR + dependency_model.clazz.name)
        end
      else
        return true if circular_dependencies.include?(dependency.name) # rubocop:disable Style/IfInsideElse
      end

      false
    end
  end

  # Represents an error for those cases when a dependency is pointing to
  # a model and this model has a dependency pointing to the original one,
  # given that both dependencies are required (hard).
  class CircularDependencyError < StandardError; end
end
