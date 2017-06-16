require 'spec_helper'

describe Export::Table do

  let(:users_table) do
    Export.table 'users' do
      replace :password, 'password'
      replace :email, ->(record) { record.email.gsub(/@.*/,"example.com") }
      replace :full_name, -> { 'Contact Name' }
      ignore :created_at, :updated_at

      def strip_email(email)
        username = email.split('@').first
        "#{username}@example.com"
      end
    end
  end

  let(:addresses_table) do
    Export.table 'addresses' do
      replace :street, -> (record) { "Not provided" }
    end
  end

  describe '#replacements' do
    it 'stores table replacements' do
      expect(addresses_table.replacements).to have_key(:street)
      expect(users_table.replacements)
        .to have_key(:password)
        .and have_key(:email)
        .and have_key(:full_name)
        .and have_key(:created_at)
        .and have_key(:updated_at)
    end
  end


end
