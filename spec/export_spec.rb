require 'spec_helper'

describe Export do
  it 'has a version number' do
    expect(Export::VERSION).not_to be nil
  end

  before do
    described_class.transform 'User' do
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

  describe '.replacements_for' do
    it do
      expect(described_class.replacements_for('User'))
        .to have_key(:password).and have_key(:email).and have_key(:full_name)
    end
  end
end
