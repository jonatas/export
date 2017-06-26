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

      create_table :comments do |t|
        t.string :description
        t.references :commentable, polymorphic: true, index: true
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

    model = proc do |table_name, &block|
      Class.new(ActiveRecord::Base) do
        self.table_name = table_name
        scope :random, -> { offset(rand(count)).first }
        instance_eval(&block) if block
      end
    end

    polymorphic = proc do |table_name, polymorphic_association|
      Class.new(ActiveRecord::Base) do
        self.table_name = table_name
        belongs_to polymorphic_association, polymorphic: true
        scope :random, -> { offset(rand(count)).first }
      end
    end

    commentable_model = proc do |table_name, &block|
      Class.new(ActiveRecord::Base) do
        self.table_name = table_name
        scope :random, -> { offset(rand(count)).first }
        has_many :comments, as: :commentable
        instance_eval(&block) if block
      end
    end

    User = model[:users]
    Category = model[:categories]
    Product = commentable_model.call(:products) { belongs_to :category }
    Order = model.call(:orders) { belongs_to :user }
    OrderItem = commentable_model.call(:order_items) { belongs_to :order; belongs_to :product }
    Comment = polymorphic[:comments, :commentable]

    users.times do
      User.create email: FFaker::Internet.email,
        name: FFaker::Name.name
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
      Comment.create description: FFaker::Lorem.paragraph, commentable: Product.random
    end

    orders.times do
      Order.create user_id: User.random.id
    end

    orders_items.times do
      OrderItem.create order_id: Order.random.id,
        product_id: Product.random.id,
        quantity: rand(3),
        price: rand(10) + rand(10).to_f / 10
    end

    (orders_items / 3).times do
      Comment.create description: FFaker::Lorem.paragraph, commentable: OrderItem.random
    end

  end

  after do
    CreateSchema.new.down
  end
end
