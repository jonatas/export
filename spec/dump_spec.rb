require 'spec_helper'

describe Export::Dump do
  subject do
    Export.dump 'light' do
      table('users') { where(id: User.order(:id).first.id) }
      all 'categories', 'products', 'orders', 'order_items'
    end
  end

  let(:first_user_id) { User.first.id }

  context '.independents' do
    include_examples 'database setup'

    it 'maps dependency between relationships' do
      expect(described_class.dependencies).to eq({
        "orders"=>["users"],
        "order_items"=>["orders", "products"],
        "products"=>["categories"]
      })

      expect(described_class.independents).to eq(%w[users categories])

      expect(described_class.polymorphic_dependencies)
        .to eq({"comments"=> { commentable: ["products", "order_items"]}})

      expect(described_class.convenient_order).to eq(
        %w[users categories orders products order_items comments])
    end
  end

  describe '#fetch_data' do

    include_examples 'database setup'
    def exported_ids
      Hash[subject.exported.map{|k,v|[k,v.map{|e|e['id']}]}]
    end

    it do
      expect { subject.fetch_data('users') }
        .to change { exported_ids['users'] }
        .to([first_user_id])
    end

    it 'does not export any order if users was not exported' do
      expect { subject.fetch_data(:orders) }
        .to change { exported_ids[:orders] }
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
        subject.fetch
        data = subject.exported
        expect(data).to have_key('users')
          .and have_key('categories')
          .and have_key('products')
          .and have_key('orders')
          .and have_key('order_items')
          .and have_key('comments')

        user_ids = [User.order(:id).first.id]
        expect(data['users'].map(&:id)).to eq(user_ids)
        expect(data['orders'].map(&:user_id).uniq).to eq(user_ids)

        commentable = data['comments'].map(&:commentable)

        expect(commentable.grep(Product) - data['products']).to be_empty
        expect(commentable.grep(OrderItem) - data['order_items']).to be_empty

      }.to change { subject.exported }
    end

    context 'transform data on fetch' do
      before do
        Export.table 'users' do
          replace :email, 'user@example.com'
        end
        subject.fetch
        subject.broadcast.resume_work
      end
      it 'works in sequence applying filters' do
        expect(subject.exported['users'].map(&:email)).to all(eq('user@example.com'))
      end
    end
  end
end
