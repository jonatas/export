module Export
  # Represents a model to be exported and its structure
  class Model
    DEPENDENCY_SEPARATOR = '•'.freeze

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

    def config(&block)
      instance_exec(&block)
    end

    def scope_by(&block)
      raise 'Cannot define scope after scope has been called.' if defined?(@scope)

      @scope_block = block
    end

    def scoped?
      @scope_block || enabled_dependencies.any? { |d| dependency_scoped?(d) }
    end

    def enabled_dependencies
      return to_enum(:enabled_dependencies) unless block_given?

      @dependencies.each do |dependency|
        next if @ignorable_dependencies.include?(dependency.name)

        yield dependency
      end
    end

    def scope
      return @scope if defined?(@scope)

      @scope = hard_scope.dup
      soft_dependencies = []

      enabled_dependencies.each do |dependency|
        if dependency.polymorphic?
          select = nil
          dependency.models.each do |model|
            next unless circular_dependency?(dependency, model) && dependency.soft?
            next unless model.scoped?

            query = model.arel_table.from
            query.projections = [
              Arel::Nodes::As.new(Arel::Nodes::Quoted.new(model.clazz.name), Arel::Nodes::SqlLiteral.new(:type.to_s)),
              model.primary_key.as(:id.to_s),
            ]

            select = select ? select.union_all(query) : query
          end

          if select
            dependencies = Arel::Table.new(dependency.name.to_s.pluralize.to_sym)
            dependencies_content = Arel::Nodes::As.new(dependencies, select)

            @scope.query.join(dependencies, Arel::Nodes::OuterJoin)
                        .on(dependencies[:type].eq(arel_table[dependency.foreign_type]).and(dependencies[:id].eq(arel_table[dependency.foreign_key])))
                        .with(dependencies_content)
            soft_dependencies << DependencyTable.new(dependency, dependencies)
          end
        else
          next unless circular_dependency?(dependency) && dependency.soft?
          next unless dependency.models.first.scoped?

          model = dependency.models.first
          table = model.arel_table
          table = table.alias("#{dependency.name}_#{table.name}") if table == arel_table

          @scope.query.join(table, Arel::Nodes::OuterJoin)
                      .on(table[model.clazz.primary_key].eq(arel_table[dependency.foreign_key]))
          soft_dependencies << DependencyTable.new(dependency, table)
        end
      end

      unless soft_dependencies.empty?
        @scope.query.projections = @clazz.column_names.map do |column|
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
      return @hard_scope if defined?(@hard_scope)

      relation = @scope_block ? @clazz.instance_exec(&@scope_block) : @clazz.all
      @hard_scope = Statement.from_relation(relation)

      enabled_dependencies.each do |dependency|
        if dependency.polymorphic?
          condition = nil
          dependency.models.each do |model|
            next unless dependency_scoped?(dependency, model)

            query = model.hard_scope.query.dup
            query.projections = [model.primary_key]

            @hard_scope.binds.concat(model.hard_scope.binds)
            foreign_condition = Arel::Nodes::Grouping.new(
              arel_table[dependency.foreign_type].eq(model.clazz.name).and(arel_table[dependency.foreign_key].in(query))
            )
            condition = condition ? condition.or(foreign_condition) : foreign_condition
          end

          @hard_scope.query.where(Arel::Nodes::Grouping.new(condition)) if condition
        else
          next unless dependency_scoped?(dependency)

          model = dependency.models.first
          query = model.hard_scope.query.dup
          query.projections = [model.primary_key]

          @hard_scope.query.where(arel_table[dependency.foreign_key].in(query))
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
      @dependencies ||= @clazz.reflections.map do |_, reflection|
        next unless reflection.is_a?(ActiveRecord::Reflection::BelongsToReflection)

        Dependency.new(reflection, @dump)
      end.compact
    end

    def circular_dependencies
      unless @circular_dependencies
        @circular_dependencies = []
        models = []

        block = proc do |dependency, path = []|
          dependency.models.each do |model|
            path << CircularDependencyPathItem.new(dependency, model)

            if model == self
              raise CircularDependencyError, "Circular dependency detected in #{self.clazz.name}##{path.first.dependency.name}." unless path.first.dependency.polymorphic? || path.any? { |i| i.dependency.soft? }

              name = path.first.dependency.name
              name = name.to_s + DEPENDENCY_SEPARATOR + path.first.model.clazz.name if path.first.dependency.polymorphic?

              @circular_dependencies << name
            elsif !models.include?(model)
              models << model
              model.enabled_dependencies.each { |d| block.call d, path.dup }
            end
          end
        end

        enabled_dependencies.each { |d| block.call d }
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

  CircularDependencyPathItem = Struct.new(:dependency, :model)
  DependencyTable = Struct.new(:dependency, :table)
end
