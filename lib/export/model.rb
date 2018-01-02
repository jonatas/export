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
      @scope_block || enabled_dependencies.any? { |d| scope_dependency?(d) }
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

      @scope = hard_scope
      soft_dependencies = []

      enabled_dependencies.each do |dependency|
        next unless circular_dependency?(dependency) && dependency.soft?
        next unless dependency.scoped?
        next if dependency.polymorphic? # TEMPORARIO

        table = @clazz.arel_table
        dependency_table = dependency.models.first.clazz.arel_table
        dependency_table = dependency_table.alias("#{dependency.name}_#{dependency_table.name}") if table == dependency_table

        join = table.join(dependency_table, Arel::Nodes::OuterJoin)
                    .on(dependency_table[dependency.models.first.clazz.primary_key].eq(table[dependency.foreign_key]))
                    .join_sources

        @scope = @scope.joins(join)
        soft_dependencies << [dependency, dependency_table]
      end

      unless soft_dependencies.empty?
        fields = @clazz.column_names.clone
        soft_dependencies.each do |dependency, table|
          next if dependency.polymorphic? # TEMPORARIO

          index = fields.index(dependency.foreign_key)
          fields[index] = table[:id].as(dependency.foreign_key)

          index = fields.index(dependency.foreign_type)
          fields[index] = table[:type].as(dependency.foreign_type) if index
        end

        @scope = @scope.select(*fields)
      end

      @scope
    end

    def ignore(*args)
      @ignorable_dependencies.push(*args)
    end

    protected

    attr_reader :clazz

    def hard_scope
      return @hard_scope if defined?(@hard_scope)

      @hard_scope = @scope_block ? @clazz.instance_exec(&@scope_block) : @clazz.all

      enabled_dependencies.each do |dependency|
        next unless scope_dependency?(dependency)

        if dependency.polymorphic?
          table = @clazz.arel_table
          binds = []
          condition = nil

          dependency.models.each do |model|
            query = model.hard_scope
            query = query.select(query.arel_attribute(query.klass.primary_key))

            binds.push(*query.bound_attributes)
            foreign_condition = Arel::Nodes::Grouping.new(
              table[dependency.foreign_type].eq(model.clazz.name).and(table[dependency.foreign_key].in(query.arel))
            )

            condition = condition ? condition.or(foreign_condition) : foreign_condition
          end

          @hard_scope = @hard_scope.where(Arel::Nodes::Grouping.new(condition))
          @hard_scope.where_clause.binds.push(*binds)
          @hard_scope.to_sql
        else
          @hard_scope = @hard_scope.where(dependency.name => dependency.models.first.hard_scope)
        end
      end

      @hard_scope
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
          path << dependency

          dependency.models.each do |model|
            if model == self
              raise CircularDependencyError, "Circular dependency detected in #{self.clazz.name}##{path.first.name}." unless path.any?(&:soft?)

              name = path.first.name
              name += DEPENDENCY_SEPARATOR + model.clazz.name if dependency.polymorphic?

              @circular_dependencies << name
            elsif !models.include?(model)
              models << model
              model.enabled_dependencies.each { |d| block.call d, path }
            end
          end
        end

        enabled_dependencies.each { |d| block.call d }
      end

      @circular_dependencies
    end

    def scope_dependency?(dependency)
      return false if circular_dependency?(dependency) && dependency.soft?
      return false unless dependency.scoped?

      true
    end

    def circular_dependency?(dependency)
      if dependency.polymorphic?
        return true if dependency.models.any? do |model|
          circular_dependencies.include?(dependency.name.to_s + DEPENDENCY_SEPARATOR + model.clazz.name)
        end
      else
        return true if circular_dependencies.include?(dependency.name) # rubocop:disable Style/IfInsideElse
      end

      false
    end

    # def add_polymorphic_dependencies
    #   current_scope = @scope
    #   polymorphic_dependencies.each do |polymorphic_association, associations|
    #     next unless requires_declare_scope?(associations)
    #     associations.each_with_index do |association_class,i|
    #       association_scope = self.class.new(association_class, @dump).scope
    #       condition = current_scope.where(polymorphic_association => association_scope)
    #       if i == 0
    #         @scope = condition
    #       else
    #         @scope = @scope.union condition
    #       end
    #     end
    #   end
    # end

    # def polymorphic_dependencies
    #   @polymorphic_dependencies ||=
    #     @clazz.reflections.select do |name, reflection|
    #       reflection.is_a?(ActiveRecord::Reflection::BelongsToReflection) &&
    #       !@clazz.column_for_attribute(reflection.foreign_key).null &&
    #       reflection.options && reflection.options[:polymorphic] == true
    #     end
    #       .values.map(&:name).inject({}) do |acc, name|
    #       assocs = polymorphic_associates_with(name)
    #       acc[name] = assocs if assocs.any?
    #       acc
    #     end
    # end

    # def polymorphic_associates_with(polymorphic_model)
    #   (self.class.interesting_models - [@clazz]).select do |clazz|
    #     reflection = clazz.reflections[@clazz.table_name]
    #     reflection && reflection.options[:as] == polymorphic_model
    #   end.map(&:name).uniq.map(&:safe_constantize)
    # end
  end

  class CircularDependencyError < StandardError; end
end
