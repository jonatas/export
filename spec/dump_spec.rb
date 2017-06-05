require 'spec_helper'

describe Export::Dump do
  subject do
    Export.dump 'production' do
      table :users, where: ["created_at >= ?", '2017-06-04']
      all :categories, :products
      table :orders, depends_on: :users
      table :order_items, depends_on: :orders
    end
  end

  describe '#options' do
    its(:options) do
      is_expected
        .to have_key(:users)
        .and have_key(:categories)
        .and have_key(:products)
        .and have_key(:orders)
        .and have_key(:order_items)
    end

    it 'hold options for each argument' do
      expect(subject.options[:users])
        .to eq(where: ["created_at >= ?", '2017-06-04'])
    end
  end

  describe '#all' do
    it 'mark options as :all' do
      options_for = subject.options.values_at(:categories, :products)
      expect(options_for).to all(eq :all)
    end
  end

  describe '#options_for' do
    it ':where' do
      expect(subject.options_for(:where, ["created_at > ?", '2017-06-04']))
    end

    it ':all' do
      expect(subject.options_for(:all,nil)).to be_nil
    end

    context 'depends_on' do
      let(:depends) { subject.options_for(:depends_on, :users) }
      it 'generates where with depends on id column' do
        expect(depends).to eq("user_id in ()")
      end

      it 'injects exported ids' do
        subject.exported[:users] = [1,2,3]
        expect(depends).to eq("user_id in (1,2,3)")
      end
    end
  end

  describe '#has_dependents?' do
    specify do
      expect(subject.has_dependents?(:users)).to be_truthy
      expect(subject.has_dependents?(:orders)).to be_truthy
      expect(subject.has_dependents?(:order_items)).to be_falsy
    end
  end

  describe '#fetch_data' do
    let(:data) do
      subject.fetch_data(:users)
    end

    class AddUsersTable < ActiveRecord::Migration
      def up
        create_table :users do |t|
          t.string :email, :name
          t.timestamps
        end

        users = [
          ["jonatasdp@gmail.com", "Jônatas Davi Paganini", '2017-06-04','2017-06-05'],
          ["leandroh@gmail.com", "Leandro Heuert", '2017-06-02','2017-06-03']
        ]
        sql = "insert into users(email, name, created_at, updated_at) values(?, ?, ?, ?)"
        users.each do |user_data|
          value = [sql, *user_data]
          sql = ActiveRecord::Base.__send__(:sanitize_sql, value)
          execute sql
        end
      end
      def down
        drop_table :users
      end
    end

    before do
      AddUsersTable.new.up
    end

    specify do
      expect(data.size).to eq(2)
    end

    it do
      expect { data }
        .to change { subject.exported }
        .from({})
        .to({users: [1,2]})
    end

    after do
      AddUsersTable.new.down
    end
  end
end
