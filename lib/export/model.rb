module Export
  class Model
    def initialize(clazz, dump)
      @clazz = clazz
      @dump = dump
      @scope = build_scope_from(@dump) || @clazz.all
      add_dependencies
      add_polymorphic_dependencies
    end

    def scope
      @scope
    end

    def build_scope_from dump
      additional_scope = dump.scope[@clazz.to_s]
      if additional_scope
        file, line_number = additional_scope.source_location
        code = File.readlines(file)[line_number-1]
        print ">> #{@clazz}: with conditions  #{code}"
        @clazz.instance_exec(&additional_scope)
      end
    end


    def add_dependencies
      dependencies.each do |column_name, dependency|
        dependency_clazz = dependency.class_name.constantize
        condition = self.class.new(dependency_clazz, @dump).scope
        if condition != dependency_clazz.all
          @scope = @scope.where(dependency.name => condition)
        end
        puts @scope.to_sql
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

    def dependencies
      @dependencies ||= @clazz
        .reflections
        .select { |_, v| v.macro == :belongs_to && !v.options.key?(:polymorphic) }
    end

    def polymorphic_dependencies
      @polymorphic_dependencies ||=
        @clazz.reflections.select do |name, reflection|
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
      @interesting_models ||= ActiveRecord::Base.descendants
    end
  end
end
