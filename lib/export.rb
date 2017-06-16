require 'export/version'
require 'active_support/inflector'
require 'active_record'
require 'export/table'
require 'export/dump'
require 'export/transform_data'

# Allow to export a specific table
module Export

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

  def self.replacements
    @replacements ||= {}
  end

  def self.replacements_for(table_name)
    replacements[table_name] && replacements[table_name].replacements
  end

  def self.clear_table_replacements!
    @replacements = nil
  end
end
