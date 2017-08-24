module Export
  class DependencyTree
    attr_reader :dependencies, :parent, :model, :metadata
    def initialize(model, metadata=nil, parent=nil)
      @model = model
      @metadata = metadata
      @parent = parent
      @dependencies = {}
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
            @dependencies["#{clazz}##{dependency.foreign_key}"] = self.class.new(clazz, dependency, self)
          end
        else
          key = "#{@model}##{dependency.foreign_key}"
          clazz = dependency.class_name.safe_constantize
          @dependencies[key] = self.class.new(clazz, dependency, self)
        end
      end
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

    def self.interesting_models
      @interesting_models ||= ActiveRecord::Base.descendants.reject(&:abstract_class).select(&:table_exists?)
    end
  end
end