require 'export/version'
require 'active_support/inflector'
require 'active_record'
require 'export/transform'
require 'export/dependency'
require 'export/statement'
require 'export/model'
require 'export/dump'
require 'export/transform_data'

require_relative 'ext/arel'

# Allow to export a specific table
module Export
  # @example
  #   Export.transform User do
  #      replace :password, 'password'
  #      replace :email, -> (record) { strip_email(record.email) }
  #      replace :full_name, -> { "Contact Name" }
  #      ignore :created_at, :updated_at
  def self.transform(clazz, &block)
    Export::Transform.new(clazz, &block)
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

  def self.transform_data(model, data)
    return data unless Export.replacements_for(model)
    Export::TransformData.new(model).process(data)
  end

  def self.replacements
    @replacements ||= {}
  end

  def self.replacements_for(model)
    replacements[model.to_s]&.replacements
  end

  def self.clear_table_replacements!
    @replacements = nil
  end
end
