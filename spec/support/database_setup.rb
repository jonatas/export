RSpec.shared_examples "database setup" do |people: 2, admins: 1, orders: 5, products: 10, categories: 4, orders_items: 30|

  class CreateSchema < ActiveRecord::Migration[5.0]
    def up
      create_table :users do |t|
        t.string :email, :name
        t.integer :current_role_id
        t.string :current_role_type
        t.timestamps
      end

      create_table :roles do |t|
        t.references :user, null: false
        t.string :type # STI
      end

      create_table :orders do |t|
        t.references :user, null: false
        t.string :status
        t.timestamps
      end

      create_table :categories do |t|
        t.string :label
        t.text :description
      end

      create_table :products do |t|
        t.references :category, null: false
        t.string :name
      end

      create_table :order_items do |t|
        t.references :order, null: false
        t.references :product, null: false
        t.integer :quantity
        t.decimal :price
        t.timestamps
      end

      create_table :comments do |t|
        t.string :description
        t.references :role, null: false
        t.references :commentable, polymorphic: true, index: true, null: false
        t.timestamps
      end

      create_table :media_items do |t|
        t.string :type, null: false, limit: 32
        t.string :name
        t.timestamps
      end
    end

    def down
      drop_table :users
      drop_table :orders
    end
  end

  before do
    CreateSchema.new.up

    class ApplicationRecord < ActiveRecord::Base

      self.abstract_class = true

      scope :random, -> { offset(rand(count)).first }
    end

    class User < ApplicationRecord
      scope :random, -> { offset(rand(count)).first }
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
    class Category < ApplicationRecord; end

    class Order < ApplicationRecord
      belongs_to :user
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

    people.times do
      Person.create user: User.create(
        email: FFaker::Internet.email,
        name: FFaker::Name.name)
    end

    admins.times do
      Admin.create user: User.create(
        email: FFaker::Internet.email,
        name: FFaker::Name.name)
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

    Order.create user_id: User.order(:id).first.id

    (orders - 1).times do
      Order.create user_id: User.random.id
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

  after do
    CreateSchema.new.down
  end
end
