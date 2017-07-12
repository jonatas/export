module Export
  class Model
    def initialize(clazz, dump)
      @clazz = clazz
      @dump = dump
    end

    def scope
      return @scope if defined?(@scope)
      @scope = build_scope_from(@dump) || @clazz.all
      add_dependencies
      add_polymorphic_dependencies
      puts "::::::: #{@clazz} #{@scope.count} :::::::::",@scope.to_sql, "::::::::::::::"
      @scope
    end

    def build_scope_from dump
      additional_scope = dump.scope[@clazz.to_s]
      if additional_scope
        file, line_number = additional_scope.source_location
        code = File.readlines(file)[line_number-1]
        @clazz.instance_exec(&additional_scope)
      end
    end

    def add_dependencies
      dependencies.each do |column_name, dependency|
        dependency_clazz = dependency.class_name.safe_constantize
        dependency_model = self.class.new(dependency_clazz, @dump)
        condition = dependency_model.scope
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

    def add_polymorphic_dependencies
      current_scope = @scope
      polymorphic_dependencies.each do |polymorphic_association, associations|
        next unless requires_declare_scope?(associations)
        associations.each_with_index do |association_class,i|
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
      dependency_clazz = dependency.class_name.safe_constantize || (eval(dependency.class_name) rescue nil)
      if dependency_clazz.nil?
        "Can't safe constantize #{dependency.class_name}."
      elsif dependency.class_name == @clazz.name
        "Recursive relationship"
      elsif dependency.foreign_key.nil?
        "Without foreign_key #{dependency.inspect}"
      elsif @clazz.column_for_attribute(dependency.foreign_key).null == true
        "Column #{dependency.foreign_key} allow null"
      elsif @clazz.column_for_attribute(dependency.foreign_key).default == "0"
        "Column #{dependency.foreign_key} default is 0"
      end
    end


    def dependencies
      @dependencies ||= @clazz.reflections.select do |attribute, dependency|
        next unless dependency.is_a?(ActiveRecord::Reflection::BelongsToReflection)
        cause = why_skip(dependency)
        if cause
          puts "#{@clazz} ignored #{dependency.class_name}: #{cause}"
          next
        end

        !dependency.options.key?(:polymorphic)
      end
    end

    def polymorphic_dependencies
      @polymorphic_dependencies ||=
        @clazz.reflections.select do |name, reflection|
          reflection.is_a?(ActiveRecord::Reflection::BelongsToReflection) &&
          !@clazz.column_for_attribute(reflection.foreign_key).null &&
          reflection.options && reflection.options[:polymorphic] == true
        end
          .values.map(&:name).inject({}) do |acc, name|
          assocs = polymorphic_associates_with(name)
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
  end
end
