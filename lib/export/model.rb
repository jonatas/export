module Export
  # Represents a model to be exported and its structure
  class Model
    DEPENDENCY_SEPARATOR = '•'.freeze
    SOFT_PREFIX = 'soft_'
    HARD_PREFIX = 'hard_'

    def initialize(clazz)
      @clazz = clazz
      @ignorable_dependencies = []
    end

    def inspect
      "#<#{self.class.name} @clazz=#{@clazz.name}>"
    end

    def load(dump)
      raise 'Cannot reload a model.' if defined?(@dump)

      @dump = dump

      load_dependencies
    end

    def reload
      @circular_dependencies = nil
      @dependencies = nil
      @hard_scope = nil
      @scope = nil

      load_dependencies
    end

    def config(&block)
      instance_exec(&block)
    end

    def scope_by(&block)
      raise 'Cannot define scope after scope has been called.' if @scope

      @scope_block = block
    end

    def scoped?
      @scope_block.present? || enabled_dependencies.any? { |d| dependency_scoped?(d) }
    end

    def enabled_dependencies
      return to_enum(:enabled_dependencies) unless block_given?

      @dependencies.each do |dependency|
        next if @ignorable_dependencies.include?(dependency.name)

        yield dependency
      end
    end

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
              node = Arel::Nodes::UnionAll.new(node, model_manager.ast)
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

        node = Arel::Nodes::Grouping.new(node) unless node.is_a?(Arel::Nodes::UnionAll)
        dependencies = Arel::Table.new("#{alias_prefix}#{dependency.name.to_s.pluralize}")

        on = dependencies[:id].eq(arel_table[dependency.foreign_key])
        on = dependencies[:type].eq(arel_table[dependency.foreign_type]).and(on) if dependency.polymorphic?

        @scope.manager
              .join(dependencies, Arel::Nodes::OuterJoin)
              .on(on)
              .prepend_with(Arel::Nodes::As.new(dependencies, node))
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

    def ignore(*args)
      @ignorable_dependencies.concat(args)
    end

    protected

    delegate :arel_table, to: :clazz

    attr_reader :clazz

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
              node = Arel::Nodes::UnionAll.new(node, model_manager.ast)
            else
              binds = model.hard_scope.binds
              node = model_manager.ast
            end
          end

          if node
            node = Arel::Nodes::Grouping.new(node) unless node.is_a?(Arel::Nodes::UnionAll)
            alias_prefix = HARD_PREFIX if dependency.models.any? { |m| m.scoped? && circular_dependency?(dependency, m) && dependency.soft? }
            manager_alias = Arel::Table.new("#{alias_prefix}#{dependency.name.to_s.pluralize}").from
            manager_alias.projections = [
              manager_alias.source.left[:type],
              manager_alias.source.left[:id]
            ]

            @hard_scope.binds.unshift(*binds)
            @hard_scope.manager
                       .where(Arel::Nodes::Grouping.new([arel_table[dependency.foreign_type], arel_table[dependency.foreign_key]]).in(manager_alias))
                       .prepend_with(Arel::Nodes::As.new(manager_alias.source.left, node))
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

    def load_dependencies
      @dependencies = @clazz.reflections.map do |_, reflection|
        next unless reflection.is_a?(ActiveRecord::Reflection::BelongsToReflection)

        Dependency.new(reflection, @dump)
      end.compact
    end

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

  class CircularDependencyError < StandardError; end

  CircularDependencyPathItem = Struct.new(:parent, :dependency, :model)
  DependencyTable = Struct.new(:dependency, :table)
end
