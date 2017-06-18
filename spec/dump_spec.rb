require 'spec_helper'

describe Export::Dump do
  subject do
    Export.dump 'light' do
      table('users') { where(id: 1) }
      all 'categories', 'products', 'orders', 'order_items'
      on_fetch_data {|t,d| puts "#{t} #{d.map(&:id)}" }
    end
  end

  context '.independents' do
    include_examples 'database setup'

    it 'maps dependency between relationships' do
      expect(described_class.dependencies).to eq({
        "orders"=>"users",
        "order_items"=>"products",
        "products"=>"categories"
      })

      expect(described_class.independents).to eq(%w[users categories])

      expect(described_class.convenient_order).to eq(
        %w[users categories orders order_items products])
    end
  end

  describe '#fetch_data' do

    include_examples 'database setup'
    let(:exported_ids) { Hash[subject.exported.map{|k,v|[k,v.map{|e|e['id']}]}] }

    it do
      expect { subject.fetch_data('users') }
        .to change { (subject.exported['users']||[]).map{|e|e['id'] } }
        .to([1])
    end

    it 'does not export any order if users was not exported' do
      expect { subject.fetch_data(:orders) }
        .to change { (subject.exported[:orders]||[]).map{|e|e['id'] } }
    end

    it 'works in sequence applying filters' do
      expect do
        subject.fetch_data('users')
        subject.fetch_data('orders')
      end.to change { subject.exported }
    end
  end

  describe '#fetch' do
    include_examples 'database setup'

    it 'works in sequence applying filters' do
      expect {
        data = subject.fetch
        expect(data).to have_key('users')
          .and have_key('categories')
          .and have_key('products')
          .and have_key('orders')
          .and have_key('order_items')


        expect(data['users'].map{|e|e['id']}).to eq([1])
        expect(data['orders'].map{|e|e['user_id']}.uniq).to eq([1])
      }.to change { subject.exported }
    end

    context 'transform data on fetch' do
      before do
        Export.table 'users' do
          replace :email, 'user@example.com'
        end
        subject.fetch
      end
      it 'works in sequence applying filters' do
        expect(subject.exported['users'].map{|e|e['email']}).to all(eq('user@example.com'))
      end
    end
  end
end
