
module Export
  class Model
    def initialize(clazz, dump)
      @clazz = clazz
      @dump = dump
    end

    def scope(current_deps=[])
      return @scope if defined?(@scope)
      @scope = build_scope_from(@dump) || @clazz.all
      add_dependencies(current_deps)
      add_polymorphic_dependencies(current_deps)
      puts "::::::: #{@clazz} #{@scope.count} :::::::::",@scope.to_sql, "::::::::::::::"
      @scope
    end

    def build_scope_from dump
      additional_scope = dump.scope[@clazz.to_s]
      if additional_scope
        @clazz.instance_exec(&additional_scope)
      end
    end

    def add_dependencies(current_deps=[])
      dependencies(current_deps).each do |column_name, dependency|
        dependency_clazz = dependency.class_name.safe_constantize
        current_deps << dependency.class_name
        dependency_model = self.class.new(dependency_clazz, @dump)
        condition = dependency_model.scope(current_deps)
        if condition != dependency_clazz.all
          @scope = @scope.where(dependency.name => condition)
        end
      end
    end

    def requires_declare_scope? associations
      associations.any? do |association_class|
        association_scope = self.class.new(association_class, @dump).scope
        association_scope != association_class.all
      end
    end

    def add_polymorphic_dependencies(current_deps=[])
      current_scope = @scope
      polymorphic_dependencies(current_deps).each do |polymorphic_association, associations|
        next unless requires_declare_scope?(associations)
        current_deps << polymorphic_association
        associations.each_with_index do |association_class,i|
          current_deps << association_class.name
          association_scope = self.class.new(association_class, @dump).scope
          condition = current_scope.where(polymorphic_association => association_scope)
          if i == 0
            @scope = condition
          else
            @scope = @scope.union condition
          end
        end
      end
    end

    def why_skip dependency
      dependent = dependency.options.has_key?(:dependent)
      return if dependent && %i[destroy delete_all].include?(dependent)

      if dependency.class_name == @clazz.name
        "Recursive relationship"
      end
    end

    def current_reflections_less(current_deps=[])
      current_deps << @clazz.name

      @clazz.reflections.select do |attribute, dependency|
        dependency.is_a?(ActiveRecord::Reflection::BelongsToReflection) &&
          !current_deps.include?(dependency.class_name)
      end
    end

    def dependencies(current_deps=[])
      current_reflections_less(current_deps).select do |_, dependency|
        cause = why_skip(dependency)
        if cause
          #puts "#{@clazz} ignored #{dependency.class_name}: #{cause}"
          next
        end

        !dependency.options.key?(:polymorphic)
      end
    end

    def polymorphic_dependencies(current_deps=[])
      current_reflections_less(current_deps).select do |_, dependency|
            dependency.options && dependency.options[:polymorphic] == true
        end.values.map(&:name).inject({}) do |acc, name|
          assocs = polymorphic_associates_with(name) - current_deps
          acc[name] = assocs if assocs.any?
          acc
        end
    end

    def polymorphic_associates_with(polymorphic_model)
      (self.class.interesting_models - [@clazz]).select do |clazz|
        reflection = clazz.reflections[@clazz.table_name]
        reflection && reflection.options[:as] == polymorphic_model
      end.map(&:name).uniq.map(&:safe_constantize)
    end

    def self.interesting_models
      @interesting_models ||= ActiveRecord::Base.descendants.reject(&:abstract_class).select(&:table_exists?)
    end

    def graph_dependencies(main = nil, current_deps=[], output=nil)
      if main.nil?
        main = @clazz.name
        output = "digraph #{ main } {"
        current_deps << main
        root = true
      end

      dependencies(current_deps).each do |column_name, dependency|
        dependency_clazz = dependency.class_name.safe_constantize
        next if dependency_clazz.nil?
        current_deps << dependency.class_name
        dependency_model = self.class.new(dependency_clazz, @dump)
        output << "\n  #{main} -> #{dependency.class_name.tr(':','')}"
        dependency_model.graph_dependencies(dependency.class_name, current_deps, output)
      end

      polymorphic_dependencies(current_deps).each do |association, classes|
        classes.each do |dependency|
          if current_deps.include?(dependency.name)
            next
          end
          current_deps << dependency.name
          output << %|\n  #{main} -> #{dependency.name.tr(':','')} [label="#{association}"]|
          dependency_model = self.class.new(dependency, @dump)
          dependency_model.graph_dependencies(dependency.name, current_deps, output)
        end
      end

      if root
        output << "\n}"
      end
      output
    end
  end
end
