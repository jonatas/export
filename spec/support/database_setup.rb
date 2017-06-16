RSpec.shared_examples "database setup" do


  class CreateSchema < ActiveRecord::Migration[5.0]
      ORDERS = [
        [1, 'finalized', '2017-06-04','2017-06-05'],
        [2, 'started',   '2017-06-03','null'],
        [3, 'shipped',   '2017-06-09','null'],
        [1, 'shipped',   '2017-06-09','2017-06-12']
      ]

      INSERT_ORDERS = "insert into orders(user_id, status, created_at, updated_at) values(?, ?, ?, ?)"


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

      user = Class.new(ActiveRecord::Base) do
        self.table_name = :users
      end

      2.times do
        user.create email: FFaker::Internet.email,
          name: FFaker::Name.name
      end

      insert ORDERS, INSERT_ORDERS
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
  end

  after do
    CreateSchema.new.down
  end
end
