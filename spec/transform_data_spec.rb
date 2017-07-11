require 'spec_helper'

describe Export::TransformData do

  include_examples 'database setup'

  before do
    Export.transform User do
      replace :email, ->(record) { strip_email(record.email) }
      replace :name, -> { 'Contact Name' }
      ignore :created_at, :updated_at

      def strip_email(email)
        username = email.split('@').first
        "#{username}@example.com"
      end
    end
  end


  describe '#process' do
    let(:transform) { described_class.new(User) }
    let(:sample_data) { User.all }
    let(:processed_data) { transform.process(sample_data) }
    let(:first_record) { processed_data.first }

    specify do
      expect(processed_data.size).to eq 3
      processed_data.each do |record|
        expect(record.name).to eq('Contact Name')
        expect(record.created_at && record.updated_at).to be_nil
      end
    end
  end
end
