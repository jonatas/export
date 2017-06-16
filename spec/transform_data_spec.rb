require 'spec_helper'

describe Export::TransformData do
  User = Struct.new(:full_name, :email, :password, :created_at, :updated_at)
  Category = Struct.new(:name)

  before do
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

  let(:users) do
    [
      User.new('Jônatas Paganini', 'jonatasdp@gmail.com', 'myPreciousSecret', Time.now, Time.now + 3600 * 24),
      User.new('Leandro Heuert', 'leandroh@gmail.com', 'LeandroLOL', Time.now, Time.now + 3600 * 24 * 2)
    ]
  end

  let(:categories) do
    [ Category.new("A"), Category.new("B") ]
  end

  let(:dump) { described_class.new('users') }
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
