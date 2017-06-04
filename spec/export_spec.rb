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
end
