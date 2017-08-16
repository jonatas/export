require 'graphviz'

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
      foreign_column = @clazz.column_for_attribute(dependency.foreign_key)
      if @clazz.where(foreign_column.name => nil).any?
        "Ignoring non strong ref to #{foreign_column}"
      elsif dependency_clazz.nil?
        "Can't safe constantize #{dependency.class_name}."
      elsif foreign_column.null
        "Foreign column #{foreign_column.inspect} allow null"
      elsif foreign_column.default == "0"
        "Foreign column #{foreign_column.inspect} default is zero"
      elsif dependency.class_name == @clazz.name
        "Recursive relationship"
      end
    end

    def dependencies
      @dependencies ||= @clazz.reflections.select do |attribute, dependency|
        next unless dependency.is_a?(ActiveRecord::Reflection::BelongsToReflection)
        cause = why_skip(dependency)
        if cause
          #puts "#{@clazz} ignored #{dependency.class_name}: #{cause}"
          next
        end

        !dependency.options.key?(:polymorphic)
      end
    end

    def polymorphic_dependencies
      @polymorphic_dependencies ||=
        @clazz.reflections.select do |name, reflection|
          reflection.is_a?(ActiveRecord::Reflection::BelongsToReflection) &&
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

    def graph_dependencies(g = nil, main = nil, current_deps={})
      if g.nil?
        g = GraphViz.new( :G, :type => :digraph )
        main = g.add_nodes(@clazz.name)
        puts "starting from #{@clazz.name}"
        root = true
      else
        puts "> going recursively on #{@clazz.name} deps: #{current_deps.keys}"
      end

      dependencies.each do |column_name, dependency|
        dependency_clazz = dependency.class_name.safe_constantize
        if current_deps.has_key?(dependency_clazz.name)
          puts "Ignoring cyclic dependency #{dependency_clazz.name}. Deps: #{current_deps.keys.inspect}"
          next
        end
        dependency_model = self.class.new(dependency_clazz, @dump)
        dependency_node = g.add_nodes(dependency_clazz.name )
        current_deps[dependency_clazz.name] = 1
        g.add_edges( main, dependency_node)
        puts "add edge #{main} => #{dependency_clazz.name}"
        dependency_model.graph_dependencies(g, dependency_node, current_deps)
      end

      polymorphic_dependencies.each do |association, classes|
        assoc_node = g.add_nodes(association.to_s)
        g.add_edges( main, assoc_node)
        classes.uniq.each do |dependency|
          if current_deps.has_key?(dependency.name)
            puts "Ignoring cyclic dependency #{dependency.name}. Deps: #{current_deps.keys.inspect}"
            next
          end
          current_deps[dependency.name] = 1
          dependency_node = g.add_nodes(dependency.name)
          puts "add edge #{association} => #{dependency.name}"
          g.add_edges( assoc_node, dependency_node)
          dependency_model = self.class.new(dependency, @dump)
          dependency_model.graph_dependencies(g, dependency_node, current_deps)
        end
      end

      if root && (dependencies.any? || polymorphic_dependencies.any?)
        filename = "#{@clazz.name.downcase}.png"
        puts "output #{filename}"
        g.output( :png => filename )
        puts "Done with file #{filename}"
        filename
      end
    end
  end
end
