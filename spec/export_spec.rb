require 'spec_helper'

describe Export do
  it 'has a version number' do
    expect(Export::VERSION).not_to be nil
  end

  let(:users_table) do
    Export.table 'users' do
      replace :password, 'password'
      replace :email, ->(record) { strip_email(record.email) }
      replace :full_name, -> { 'Contact Name' }
      ignore :created_at, :updated_at

      def strip_email(email)
        username = email.split('@').first
        "#{username}@example.com"
      end
    end
  end

  describe '.table' do
    subject { users_table }
    its(:name) { is_expected.to include('users') }
    its(:replacements) do
      is_expected
        .to include(:password, :email, :full_name, :created_at, :updated_at)
    end

    context 'without block definition' do
      let(:table_without_spec) do
      end
      specify do
        expect do
          Export.table 'test'
        end.not_to raise_error
      end
    end
  end

  describe '.full_table' do
    context 'single table' do
      subject { Export.full_table 'users' }
      its(:name) { is_expected.to include('users') }
      its(:replacements) { is_expected.to be_empty }
    end

    context 'multiple tables' do
      subject { Export.full_table 'users', 'categories' }
      specify do 
        expect(subject.map(&:name)).to eq(['users', 'categories'])
        expect(subject.map(&:replacements)).to all(be_empty)
      end
    end
  end

  User = Struct.new(:full_name, :email, :password, :created_at, :updated_at)
  Category = Struct.new(:name)

  let(:users) do
    [
      User.new('Jônatas Paganini', 'jonatasdp@gmail.com', 'myPreciousSecret', Time.now, Time.now + 3600 * 24),
      User.new('Leandro Heuert', 'leandroh@gmail.com', 'LeandroLOL', Time.now, Time.now + 3600 * 24 * 2)
    ]
  end

  let(:categories) do
    [ Category.new("A"), Category.new("B") ]
  end

  describe described_class::DumpTable do
    let(:dump) { described_class.new(users_table) }
    let(:sample_data) { users }

    describe '#process' do
      let(:processed_data) { dump.process(sample_data) }
      let(:first_record) { processed_data.first }
      specify do
        expect(processed_data.size).to eq 2
        processed_data.each do |record|
          expect(record.password).to eq('password')
          expect(record.full_name).to eq('Contact Name')
          expect(record.created_at && record.updated_at).to be_nil
        end
      end
    end
  end

  describe described_class::Dump do
    let(:since) { Time.now - 3600 * 24 * 30 }
    subject do
      Export.dump 'production' do
        table :users, where: ["created_at > ?", '2017-06-04']
        all :categories, :products
        table :orders, depends_on: :users
        table :order_items, depends_on: :orders
      end
    end

    describe '.table' do
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
          .to eq(where: ["created_at > ?", '2017-06-04'])
      end
    end

    describe '.all' do
      it 'mark options as :all' do
        options_for = subject.options.values_at(:categories, :products)
        expect(options_for).to all(eq :all)
      end
    end

    describe '.options_for' do
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

    describe '.has_dependents?' do
      specify do
        expect(subject.has_dependents?(:users)).to be_truthy
        expect(subject.has_dependents?(:orders)).to be_truthy
        expect(subject.has_dependents?(:order_items)).to be_falsy
      end
    end
  end
end
