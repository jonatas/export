RSpec.shared_context 'database creation' do # rubocop:disable RSpec/ContextWording
  class CreateSchema < ActiveRecord::Migration[5.0]
    def up
      create_table :users do |t|
        t.string :email, :name
        t.integer :current_role_id
      end

      create_table :roles do |t|
        t.references :user, null: false
        t.string :type # STI
      end

      create_table :organizations do |t|
        t.string :name
      end

      create_table :branches do |t|
        t.references :organization, null: false
        t.string :code
      end

      create_table :companies do |t|
        t.references :organization, null: false
        t.string :name
        t.references :last_order, null: true
      end

      create_table :contacts do |t|
        t.references :company, null: false
        t.string :name
        t.string :phone
      end

      create_table :orders do |t|
        t.references :user, null: false
        t.references :contact, null: false
        t.string :status
      end

      create_table :categories do |t|
        t.references :parent, null: true
        t.string :label
        t.text :description
      end

      create_table :products do |t|
        t.references :category, null: true
        t.string :name
      end

      create_table :order_items do |t|
        t.references :order, null: false
        t.references :product, null: false
        t.integer :quantity
        t.decimal :price
      end

      create_table :comments do |t|
        t.string :description
        t.references :role, null: false
        t.references :commentable, polymorphic: true, index: true, null: false
      end
    end

    def down
      drop_table :users
      drop_table :roles
      drop_table :orders
      drop_table :categories
      drop_table :products
      drop_table :order_items
      drop_table :comments
    end
  end

  before do
    ActiveRecord::Migration.verbose = false
    CreateSchema.new.up

    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true

      scope :random, -> { offset(rand(count)).first }
    end

    class User < ApplicationRecord
      has_many :orders

      has_many :roles, dependent: :destroy, inverse_of: :user, autosave: false, validate: false
      belongs_to :current_role, class_name: 'Role'
    end

    class Role < ApplicationRecord
      belongs_to :user, dependent: :destroy, autosave: true, inverse_of: :roles

      after_create do
        self.user.update_attributes current_role: self
      end
    end

    class Person < Role; end
    class Admin < Role; end

    class Category < ApplicationRecord
      belongs_to :parent, class_name: 'Category'
    end

    class Organization < ApplicationRecord
      has_many :companies
      has_many :branches
    end

    class Branch < ApplicationRecord
      belongs_to :organization
    end

    class Company < ApplicationRecord
      belongs_to :organization
      belongs_to :last_order, class_name: 'Order'
    end

    class Contact < ApplicationRecord
      belongs_to :company
    end

    class Order < ApplicationRecord
      belongs_to :user
      belongs_to :contact
    end

    class Product < ApplicationRecord
      belongs_to :category
      has_many :comments, as: :commentable
    end

    class OrderItem < ApplicationRecord
      belongs_to :order
      belongs_to :product
      has_many :comments, as: :commentable
    end

    class Comment < ApplicationRecord
      belongs_to :role
      belongs_to :commentable, polymorphic: true
    end

    class ActiveRecord::Relation
      alias old_pretty_print pretty_print
      def pretty_print(q)
        q.text(self.to_sql)
      end
    end

    class Arel::SelectManager
      alias old_pretty_print pretty_print
      def pretty_print(q)
        q.text(self.to_sql)
      end
    end
  end

  after do
    class ActiveRecord::Relation
      alias pretty_print old_pretty_print
    end

    class Arel::SelectManager
      alias pretty_print old_pretty_print
    end

    CreateSchema.new.down
    ActiveRecord::Migration.verbose = true
  end
end

RSpec.shared_context 'database seed' do |people: 2, admins: 1, organizations: 1, branches: 1, companies: 1, contacts: 2, orders: 5, products: 10, categories: 4, orders_items: 30| # rubocop:disable RSpec/ContextWording, Metrics/ParameterLists
  before do
    people.times do
      Person.create user: User.create(
        email: FFaker::Internet.email,
        name: FFaker::Name.name
      )
    end

    admins.times do
      Admin.create user: User.create(
        email: FFaker::Internet.email,
        name: FFaker::Name.name
      )
    end

    categories.times do
      Category.create label: FFaker::Product.model,
                      description: FFaker::Lorem.paragraph
    end

    products.times do
      Product.create name: FFaker::Product.name,
                     category_id: Category.random.id
    end

    (products / 2).times do
      Comment.create description: FFaker::Lorem.paragraph,
                     commentable: Product.random,
                     role: Role.random
    end

    organizations.times do
      Organization.create name: FFaker::Name.name
    end

    branches.times do
      Branch.create code: FFaker::Name.name,
                    organization_id: Organization.random.id
    end

    companies.times do
      Company.create name: FFaker::Name.name,
                     organization_id: Organization.random.id
    end

    contacts.times do
      Contact.create name: FFaker::Name.name,
                     phone: FFaker::PhoneNumber.phone_number,
                     company_id: Company.random.id
    end

    orders.times do |i|
      Order.create user_id: (i == 0 ? User.order(:id).first.id : User.random.id),
                   contact: Contact.random
    end

    orders_items.times do
      OrderItem.create order_id: Order.random.id,
                       product_id: Product.random.id,
                       quantity: rand(3),
                       price: rand(10) + rand(10).to_f / 10
    end

    (orders_items / 3).times do
      Comment.create description: FFaker::Lorem.paragraph,
                     commentable: OrderItem.random,
                     role: Role.random
    end
  end
end

RSpec.shared_context 'database setup' do |people: 2, admins: 1, organizations: 1, branches: 1, companies: 1, contacts: 2, orders: 5, products: 10, categories: 4, orders_items: 30| # rubocop:disable RSpec/ContextWording, Metrics/ParameterLists
  include_context 'database creation'
  include_context 'database seed', people: people, admins: admins, organizations: organizations, branches: branches, companies: companies, contacts: contacts, orders: orders, products: products, categories: categories, orders_items: orders_items
end
