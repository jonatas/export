require 'spec_helper'

describe Export::Dump do
  include_context 'database creation'

  let(:dump) { described_class.new }

  describe 'dump info' do
    subject { dump.all_models }

    describe 'ignored' do
      before do
        dump.config do
          model(User).ignore
          model(Role).ignore
          model(Branch).ignore_dependency :organization
        end
      end

      it do
        is_expected.to include(
          have_attributes(
            clazz: User,
            ignore?: true
          ),
          have_attributes(
            clazz: Role,
            ignore?: true
          ),
          have_attributes(
            clazz: Organization,
            ignore?: false
          ),
          have_attributes(
            clazz: Branch,
            ignore?: false
          )
        ).and satisfy { |ms| ms.count(&:ignore?) == 2 }
      end
    end

    describe 'models' do
      include_context 'database seed'

      context 'when no scope is defined' do
        it do
          is_expected.to include(
            have_attributes(
              clazz: Product,
              full_count: 10,
              scope_count: 10,
              scope_percentual: 1
            ),
            have_attributes(
              clazz: Organization,
              full_count: 1,
              scope_count: 1,
              scope_percentual: 1
            )
          )
        end
      end

      context 'when scope is defined directly' do
        before do
          User.count

          dump.config do
            model(Product) do
              scope_by { where(id: [2, 4, 6]) }
            end
          end
        end

        it do
          is_expected.to include(
            have_attributes(
              clazz: Product,
              full_count: 10,
              scope_count: 3,
              scope_percentual: 0.3
            )
          )
        end
      end
    end
  end
end
