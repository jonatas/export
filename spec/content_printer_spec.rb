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
      end

      let(:batch_size) { 2 }

      it do
        is_expected.to eq <<~SQL
          INSERT INTO users (id, email, name, current_role_id) VALUES (
            (1, 'jamika@conroy.ca', 'Yuki Grady', NULL),
            (2, 'elizabeth_christiansen@metz.info', 'Lisandra Dach', NULL)
          );
          INSERT INTO users (id, email, name, current_role_id) VALUES (
            (3, 'maria_ferry@schoenfisher.info', 'Tennille Cummerata', NULL)
          );
          INSERT INTO organizations (id, name) VALUES (
            (1, 'Lindsey Mertz')
          );
        SQL
      end
    end
  end
end
