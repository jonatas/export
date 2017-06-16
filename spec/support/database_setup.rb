RSpec.shared_examples "database setup" do |users: 2, orders: 5, products: 10, categories: 4, orders_items: 30|

  class CreateSchema < ActiveRecord::Migration[5.0]
    def up
      create_table :users do |t|
        t.string :email, :name
        t.timestamps
      end

      create_table :orders do |t|
        t.references :user
        t.string :status
        t.timestamps
      end

      create_table :categories do |t|
        t.string :label
        t.text :description
      end

      create_table :products do |t|
        t.references :category
        t.string :name
      end

      create_table :order_items do |t|
        t.references :order, :product
        t.integer :quantity
        t.decimal :price
        t.timestamps
      end

    end

    def down
      drop_table :users
      drop_table :orders
    end

    def insert data, sql
      data.each do |values|
        value = [sql, *values]
        cmd = ActiveRecord::Base.__send__(:sanitize_sql, value)
        execute cmd
      end
    end

  end

  before do
    CreateSchema.new.up
    model = proc do |table_name|
      Class.new(ActiveRecord::Base) do
        self.table_name = table_name
        scope :random, -> { offset(rand(count)).first }
      end
    end

    user = model[:users]
    category = model[:categories]
    product = model[:products]
    order = model[:orders]
    order_items = model[:order_items]

    users.times do
      user.create email: FFaker::Internet.email,
        name: FFaker::Name.name
    end

    categories.times do
      category.create label: FFaker::Product.model,
        description: FFaker::Lorem.paragraph
    end

    products.times do
      product.create name: FFaker::Product.name,
        category_id: category.random.id
    end

    orders.times do
      order.create user_id: user.random.id
    end

    orders_items.times do
      order_items.create order_id: order.random.id,
        product_id: product.random.id,
        quantity: rand(3),
        price: rand(10) + rand(10).to_f / 10

    end

  end

  after do
    CreateSchema.new.down
  end
end
