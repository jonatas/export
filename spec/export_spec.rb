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

  User = Struct.new(:full_name, :email, :password, :created_at, :updated_at)
  describe described_class::Dump do
    let(:dump) { described_class.new(users_table) }
    let(:sample_data) do
      [
        User.new('Jônatas Paganini', 'jonatasdp@gmail.com', 'myPreciousSecret', Time.now, Time.now + 3600 * 24),
        User.new('Leandro Heuert', 'leandroh@gmail.com', 'LeandroLOL', Time.now, Time.now + 3600 * 24 * 2)
      ]
    end

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
end
