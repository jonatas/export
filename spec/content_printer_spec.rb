require 'spec_helper'

describe Export::ContentPrinter do
  include_context 'database creation'

  let(:io) { StringIO.new }
  let(:dump) { Export::Dump.new }
  let(:batch_size) { 10 }
  let(:printer) { described_class.new(dump, io, batch_size: batch_size) }

  describe 'print' do
    subject { printer.print.string }

    context 'when no scope is defined' do
      before do
        User.create email: 'jamika@conroy.ca',
                    name: 'Yuki Grady'
        User.create email: 'elizabeth_christiansen@metz.info',
                    name: 'Lisandra Dach'
        User.create email: 'maria_ferry@schoenfisher.info',
                    name: 'Tennille Cummerata'
        Organization.create name: 'Lindsey Mertz'

        dump.config do
          model(User).ignore_columns :created_at
          model(User).column(:updated_at).nullify
          column(:email) do
            replace
          end
        end
      end

      let(:batch_size) { 2 }

      it do
        is_expected.to eq <<~SQL
          INSERT INTO users (id, email, name, current_role_id, updated_at) VALUES (
            (1, 'jamika+conroy.ca@example.com', 'Yuki Grady', NULL, NULL),
            (2, 'elizabeth_christiansen+metz.info@example.com', 'Lisandra Dach', NULL, NULL)
          );
          INSERT INTO users (id, email, name, current_role_id, updated_at) VALUES (
            (3, 'maria_ferry+schoenfisher.info@example.com', 'Tennille Cummerata', NULL, NULL)
          );
          INSERT INTO organizations (id, name) VALUES (
            (1, 'Lindsey Mertz')
          );
        SQL
      end
    end
  end
end
