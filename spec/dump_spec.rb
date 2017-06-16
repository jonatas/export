require 'spec_helper'

describe Export::Dump do
  subject do
    Export.dump 'production' do
      table :users, where: ["id in (?)",[1]]
      all :categories, :products
      table :orders, depends_on: -> { ["user_id in (?)", ids_for_exported(:users) ] }
      table :order_items, depends_on: -> { ["order_id in (?)", ids_for_exported(:orders) ] }
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
    it 'where:' do
      expect(subject.options_for(:where, ["created_at > ?", '2017-06-04']))
    end

    context 'depends_on:' do
      include_examples 'database setup'
      let(:options_for) do
        subject.options_for(:depends_on, -> { ["user_id in (?)", ids_for_exported(:users)] })
      end

      it 'generates where with depends on id column' do
        expect(options_for).to eq("user_id in (1)")
      end
    end

  end

  describe '#fetch_data' do

    include_examples 'database setup'
    let(:exported_ids) { Hash[subject.exported.map{|k,v|[k,v.map{|e|e['id']}]}] }

    it do
      expect { subject.fetch_data(:users) }
        .to change { (subject.exported[:users]||[]).map{|e|e['id'] } }
        .to([1])
    end

    it 'does not export any order if users was not exported' do
      expect { subject.fetch_data(:orders) }
        .to change { (subject.exported[:orders]||[]).map{|e|e['id'] } }
    end

    it 'works in sequence applying filters' do
      expect do
        subject.fetch_data(:users)
        subject.fetch_data(:orders)
      end.to change { subject.exported }
    end
  end

  describe '#fetch' do
    include_examples 'database setup'

    it 'works in sequence applying filters' do
      expect {
        data = subject.fetch

        expect(data).to have_key(:users)
          .and have_key(:categories)
          .and have_key(:products)
          .and have_key(:orders)
          .and have_key(:order_items)

        expect(data[:users].map{|e|e['id']}).to eq([1])
        expect(data[:orders].map{|e|e['user_id']}.uniq).to eq([1])
      }.to change { subject.exported }
    end
  end
end
