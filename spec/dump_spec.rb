require 'spec_helper'

describe Export::Dump do
  subject do
    Export.dump 'production' do
      table :users, where: ["id in (?)",[1]]
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
        .to eq(where: ["id in (?)", [1]])
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

  describe '#fetch_order' do
    let(:order) { subject.fetch_order }
    it { expect(order).to eq [:users, :orders, :categories, :products, :order_items] }
  end

  describe '#fetch_data' do

    include_examples 'database setup'

    it do
      expect { subject.fetch_data(:users) }
        .to change { subject.exported }
        .from({}).to({users: [1]})
    end

    it 'does not export any order if users was not exported' do
      expect { subject.fetch_data(:orders) }
        .to change { subject.exported }
        .from({}).to({orders: []})
    end

    it 'works in sequence applying filters' do
      expect do
        subject.fetch_data(:users)
        subject.fetch_data(:orders)
      end
        .to change { subject.exported }
        .from({})
        .to({users: [1], orders: [1,4]})
    end
  end

  describe '#fetch' do

    include_examples 'database setup'

    it 'works in sequence applying filters' do
      expect { subject.fetch }
        .to change { subject.exported }
        .from({})
        .to({users: [1], orders: [1,4]})
    end

  end
end
