module Export
  # Transform model attributes declaring replacements
  #
  # example:
  # Export.transform User do
  #   replace :full_name, -> { FFaker::Name.name }
  #   replace :password, 'password'
  #   replace :email, -> (r) { "#{r.email.split('@').first}@example.com" }
  #   ignore :created_at, :updated_at
  # end
  class Transform

    attr_accessor :model
    attr_reader :replacements

    def initialize(model, &block)
      self.model = model
      @replacements = {}
      Export.replacements[model.to_s] = self
      instance_exec(&block)
    end

    def replace(info, with_value)
      @replacements[info] ||= []
      @replacements[info] << with_value
    end

    def ignore(*columns)
      columns.each do |column|
        replace(column, nil)
      end
    end
  end
end
