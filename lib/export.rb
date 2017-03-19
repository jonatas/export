require 'export/version'

# Allow to export a specific table
module Export
  # Table abstract use cases for each case.
  # You can set specific `.replacements` for
  # each field desired to be modified before dump.
  class Table
    attr_accessor :name
    attr_reader :replacements

    def initialize(name:)
      self.name = name
      @replacements = {}
    end

    def replace(info, with_value)
      @replacements[info] ||= []
      @replacements[info] << with_value
    end
  end

  # Dump a table with specific replacements
  class Dump
    attr_reader :table
    def initialize(table)
      @table = table
    end

    def process(data)
      new_data = data.map do |record|
        apply_replacements!(record)
      end
      new_data
    end

    private

    def apply_replacements!(record)
      table.replacements.each do |field, modifiers|
        modifiers.each do |modifier|
          value = value_from(modifier, record)
          record.public_send("#{field}=", value)
        end
      end
      record
    end

    def value_from(modifier, record)
      return modifier if modifier.is_a?(String)
      if modifier.arity.zero?
        modifier.call
      else
        modifier.call(record)
      end
    end
  end

  # @example
  #   Export.table :users do
  #      replace :password, 'password'
  #      replace :email, -> (record) { strip_email(record.email) }
  #      replace :full_name, -> { "Contact Name" }
  def self.table(name, &block)
    object = Export::Table.new(name: name)
    object.instance_exec(&block)
    object
  end
end
