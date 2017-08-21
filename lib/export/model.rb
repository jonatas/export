
module Export
  class Model


    def initialize(clazz, dump=nil)
      raise "Invalid class: #{clazz}" if clazz.nil? || !(clazz < ActiveRecord::Base)
      @clazz = clazz
      @dump = dump
    end

    def scope(current_deps=Set.new)
      return @scope if defined?(@scope)
      @scope = build_scope_from(@dump) || @clazz.all
      current_deps << @clazz.name
      add_dependencies(current_deps)
      add_polymorphic_dependencies(current_deps)
      @scope
    end

    def build_scope_from dump
      additional_scope = dump.scope[@clazz.to_s] if dump
      if additional_scope
        @clazz.instance_exec(&additional_scope)
      end
    end

    def scope_for(clazz, current_deps=Set.new)
      self.class.new(clazz, @dump).scope(current_deps.dup)
    end

    def add_dependencies(current_deps=Set.new)
      dependencies(current_deps).each do |column_name, dependency|
        dependency_clazz = dependency.class_name.safe_constantize
        next if dependency_clazz.nil? || current_deps.include?(dependency.class_name)
        current_deps << dependency.class_name
        condition = scope_for(dependency_clazz, current_deps)
        if condition != dependency_clazz.all
          @scope = @scope.where(dependency.name => condition)
        end
      end
    end

    def add_polymorphic_dependencies(current_deps=Set.new)
      current_scope = @scope
      polymorphic_dependencies(current_deps).each do |polymorphic_association, associations|
        associations.each_with_index do |association_class,i|
          next if current_deps.include?(association_class.name)
          association_scope = scope_for(association_class, current_deps)
          condition = current_scope.where(polymorphic_association => association_scope)
          if i == 0
            @scope = condition
          else
            @scope = @scope.union condition
          end
        end
      end
    end

    def current_reflections_less(current_deps=Set.new)
      current_deps << @clazz.name

      @clazz.reflections.select do |attribute, dependency|
        dependency.is_a?(ActiveRecord::Reflection::BelongsToReflection) &&
        !current_deps.include?(dependency.class_name)
      end
    end

    def dependencies(current_deps=Set.new)
      current_reflections_less(current_deps).select do |_, dependency|
        next unless dependency.class_name.safe_constantize
        dependent = dependency.options.has_key?(:dependent)
        next if dependent && %i[destroy delete_all].include?(dependent)
        next if dependency.options.key?(:polymorphic)
        dependency.class_name != @clazz.name
      end
    end

    def polymorphic_dependencies(current_deps=Set.new)
      current_reflections_less(current_deps).select do |_, dependency|
            dependency.options && dependency.options[:polymorphic] == true
        end.values.map(&:name).inject({}) do |acc, name|
          assocs = polymorphic_associates_with(name).select{|c|!current_deps.include?(c.name)}
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

    def describe
      return @clazz.name if @dump.nil?
      count = scope.count
      total_count = @clazz.count
      percent = (count.to_f / total_count) * 100.0
      "#{percent.round(2)}% #{@clazz.name}"
    end

    def graph_dependencies(main = nil, current_deps=Set.new, output=nil)
      if main.nil?
        main = @clazz.name
        output = "digraph #{ main } {"
        output << %|\n  #{ main } [label="#{describe}"]|
        current_deps << main
        root = true
      end

      connect = -> (from, to, label=nil) do
        connection = "\n  #{from.to_s.tr(':','')} -> #{to.to_s.tr(':','')}"
        unless output.include?(connection)
          output << connection
          output << " [label=\"#{label}\"]" if label
        end
      end

      dependencies(current_deps).each do |column_name, dependency|
        dependency_clazz = dependency.class_name.safe_constantize
        next if dependency_clazz.nil? || current_deps.include?(dependency.class_name)
        current_deps << dependency.class_name
        dependency_model = self.class.new(dependency_clazz, @dump)
        output << %|\n  #{ dependency.class_name} [label="#{dependency_model.describe}"]|
        connect[main, dependency.class_name]
        dependency_model.graph_dependencies(dependency.class_name, current_deps.dup, output)
      end

      polymorphic_dependencies(current_deps).each do |association, classes|
        classes.each do |dependency|
          next if current_deps.include?(dependency.name)
          current_deps << dependency.name
          dependency_model = self.class.new(dependency, @dump)
          output << %|\n  #{ dependency.name} [label="#{dependency_model.describe}"]|
          connect[main, dependency.name, association]
          dependency_model.graph_dependencies(dependency.name, current_deps.dup, output)
        end
      end

      if root
        output << "\n}"
      end
      output
    end
  end
end
