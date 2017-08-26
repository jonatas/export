module Export
  class DependencyTree
    attr_reader :dependencies, :parent, :model, :metadata
    def initialize(model, metadata: nil, parent: nil, except_keys: nil)
      @model = model
      @metadata = metadata
      @parent = parent
      @dependencies = {}
      @except_keys = except_keys
    end

    def except_keys
      @except_keys || @parent&.except_keys
    end

    def class_name
      @metadata&.class_name || @model.name
    end

    def name
      @metadata&.name || @model.downcase
    end

    def root?
      @parent == nil
    end

    def cyclic?(dependency)
      include_dependency?(dependency) ||
      any_parent? {|dep| dep.include_dependency?(dependency) }
    end

    def interesting_reflections
      return [] if @model.nil?
      @model.reflections.select do |attribute, dependency|
        dependency.is_a?(ActiveRecord::Reflection::BelongsToReflection) &&
        !include_dependency?(dependency)
      end.values
    end

    def dependencies
      build_dependencies if @dependencies.empty?
      @dependencies
    end

    def build_dependencies
      interesting_reflections.each do |dependency|
        add_dependency(dependency)
      end
      @dependencies
    end

    def include_dependency?(dependency)
      @model.name == dependency.class_name ||
        @dependencies.any?{|_, dep|dep.class_name == dependency.class_name &&
                                   dep.name == dependency.name }
    end

    def any_parent?(&block)
      return false if root?
      node = self
      begin
        node = node.parent
        if block.call(node)
          return true
        end
      end while !node.root?
      false
    end

    def add_dependency dependency
      unless cyclic?(dependency)
        if polymorphic?(dependency)
          polymorphic_associations(dependency).map do |clazz|
            add_dependency_if_needed clazz, dependency
          end
        else
          clazz = dependency.class_name.safe_constantize
          add_dependency_if_needed clazz, dependency
        end
      end
    end

    def add_dependency_if_needed(clazz, dependency)
      key = "#{polymorphic?(dependency) ? clazz : @model}##{dependency.foreign_key}"
      return if except_keys.include?(key)
      @dependencies[key] = self.class.new(clazz, metadata: dependency, parent: self)
    end

    def polymorphic?(reflection=@metadata)
      return false unless reflection
      reflection.options && reflection.options[:polymorphic] == true
    end

    def label
      @model.to_s.tr(':','')
    end

    def main_output
      %|\n  #{ label } [label="#{label}"]|
    end

    def to_s(output="")
      if root?
        output = "digraph #{ label } {"
        output << main_output
      end

      dependencies.each do |key, dependency_tree|
        dep_label = dependency_tree.main_output
        dep_connection = "\n  #{self.label} -> #{dependency_tree.label} [label=\"#{key}\"]"
        output << dep_label unless output.include?(dep_label)
        output << dep_connection unless output.include?(dep_connection)
        dependency_tree.to_s(output)
      end

      if root?
        output << "\n}"
      end
      output
    end

    def polymorphic_associations(dependency)
      (self.class.interesting_models - [@model]).select do |clazz|
        reflection = clazz.reflections[dependency.active_record.table_name]
        reflection && reflection.options[:as] == dependency.name
      end.map(&:name).uniq.map(&:safe_constantize)
    end

    def fetch(additional_scope = {}, ignore_keys = [])
      scope =
        if additional_scope.has_key?(@model.to_s)
          @model.instance_exec(&additional_scope[@model.to_s])
        else
          @model.all
        end
      unless dependencies.empty?
        polymorphics = []
        dependencies.each do |key, dep|
          next if ignore_keys.include?(key)
          if dep.polymorphic?
            polymorphics << dep
            next
          end
          puts "#{@model} -> #{key}"
          additional_where = dep.fetch(additional_scope, ignore_keys)
          if additional_where != dep.model.all
            puts "where #{dep.name} => #{additional_where.to_sql.split("WHERE ").last}"
            scope = scope.where(dep.name => additional_where)
          end
        end
        unless polymorphics.empty?
          current_scope = scope.dup
          polymorphics.each_with_index do |dep, i|
            condition = current_scope.where(dep.name => dep.fetch(additional_scope, ignore_keys))
            if i == 0
              scope = condition
            else
              scope = scope.union condition
            end
          end
        end
      end
      puts scope.to_sql
      scope
    end

    def self.interesting_models
      @interesting_models ||= ActiveRecord::Base.descendants.reject(&:abstract_class).select(&:table_exists?)
    end
  end
end
