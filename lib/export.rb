require 'export/version'
require 'active_support/inflector'
require 'active_record'

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

    def ignore(*columns)
      columns.each do |column|
        replace(column, nil)
      end
    end
  end

  # Dump a table with specific replacements
  class DumpTable
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
          value = modifier && value_from(modifier, record)
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

  class Dump
    attr_reader :options, :exported

    def initialize(schema, &block)
      @schema = schema
      @options = {}
      @exported = {}
      instance_exec(&block) if block_given?
    end

    def table name, **options
      @options[name] = options
    end

    def all *tables
      tables.each do |table|
        @options[table] = :all
      end
    end

    def options_for(key, value)
      if key == :where
        " where #{sql_condition_for(value)}"
      elsif key == :all
        # no conditions
      elsif key == :depends_on
        "#{value.to_s.singularize}_id in (#{exported_ids_for(value).join(',')})"
      else
        fail "what #{key} does? The value is: #{value}"
      end
    end
    def process
      @schema.map do |table, data|

        table.process(data)
      end
    end

    def sql_condition_for(value)
      ActiveRecord::Base.__send__(:sanitize_sql, value)
    end

    def exported_ids_for(table)
      @exported[table] || []
    end

    def has_dependents? table
      @options.values.grep(Hash).any?{|v| v[:depends_on] && v[:depends_on] == table}
    end
  end

  # @example
  #   Export.table :users do
  #      replace :password, 'password'
  #      replace :email, -> (record) { strip_email(record.email) }
  #      replace :full_name, -> { "Contact Name" }
  #      ignore :created_at, :updated_at
  def self.table(name, &block)
    object = Export::Table.new(name: name)
    object.instance_exec(&block) if block_given?
    object
  end

  def self.full_table(*names)
    tbls = names.map(&method(:table))
    tbls.size > 1 ? tbls : tbls[0]
  end

  # @example
  #   Export.dump 'production' do
  #     table :users, where: ["created_at > ?",Time.now - 3600 * 24 * 30]
  #     all :categories, :products
  #     table :orders, depends_on: :users, if: -> (order) { order.valid_for_export? }
  #     table :order_items, depends_on: :orders
  #   end
  def self.dump(schema_name, &block)
    Export::Dump.new(schema_name, &block)
  end
end
