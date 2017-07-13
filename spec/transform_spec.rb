require 'spec_helper'

describe Export::Transform do

  before do
    described_class.new 'User' do
      replace :password, 'password'
      replace :email, ->(record) { record.email.gsub(/@.*/,"example.com") }
      replace :name, -> { 'Contact Name' }
      ignore :created_at, :updated_at

      def strip_email(email)
        username = email.split('@').first
        "#{username}@example.com"
      end
    end
  end

  describe '#replacements' do
    it 'stores table replacements' do
      expect(Export.replacements_for('User')).to have_key(:email)
        .and have_key(:name)
        .and have_key(:created_at)
        .and have_key(:updated_at)
    end
  end


end
