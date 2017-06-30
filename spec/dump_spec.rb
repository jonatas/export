require 'spec_helper'

describe Export::Dump do
  subject do
    Export.transform User do
      replace :email, 'user@example.com'
    end

    Export.dump 'light' do
      model(User) { where(id: User.order(:id).first.id) }
      on_fetch_error {|clazz,e,m| require 'pry'; binding.pry  }
    end
  end

  include_examples 'database setup'

  let(:first_user_id) { User.first.id }

  describe '#fetch_data' do
    def exported_ids
      Hash[subject.exported.map{|k,v|[k,v.map{|e|e['id']}]}]
    end

    it do
      expect { subject.fetch_data(User) }
        .to change { exported_ids['User'] }
        .to([first_user_id])
    end

    it 'does not export any order if users was not exported' do
      expect { subject.fetch_data(Order) }
        .to change { exported_ids['Order'] }
    end

    it 'works in sequence applying filters' do
      expect do
        subject.fetch_data(User)
        subject.fetch_data(Order)
      end.to change { subject.exported }
    end
  end

  describe '#fetch' do

    before { subject.fetch }

    it 'works in sequence applying filters' do
      data = subject.exported
      expect(data).to have_key('User')
        .and have_key('Category')
        .and have_key('Product')
        .and have_key('Order')
        .and have_key('OrderItem')
        .and have_key('Comment')

      user_ids = [User.order(:id).first.id]
      expect(data['User'].map(&:id)).to eq(user_ids)
      expect(data['Order'].map(&:user_id).uniq).to eq(user_ids)

      commentable = data['Comment'].map(&:commentable)
      expect(commentable.grep(Product).map(&:id) - data['Product'].map(&:id)).to be_empty
      expect(commentable.grep(OrderItem).map(&:id) - data['OrderItem'].map(&:id)).to be_empty

    end

    context 'transform data on fetch' do
      before do
        subject.fetch
      end
      it 'works in sequence applying filters' do
        expect(subject.exported['User'].map(&:email)).to all(eq('user@example.com'))
      end
    end
  end
end
