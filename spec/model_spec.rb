require 'spec_helper'
require 'pry'

describe Export::Model do
  include_context 'database creation'

  let(:dump) { Export::Dump.new }

  describe 'configuration' do
    subject { dump.model_for(clazz) }

    let(:clazz) { Organization }

    context 'when loading the model again' do
      it { expect { subject.load(dump) }.to raise_error('Cannot reload a model.') }
    end

    context 'when changing scope after calling #scope' do
      before { subject.scope }

      it { expect { subject.scope_by { -> {} } }.to raise_error('Cannot define scope after scope has been called.') }
    end
  end

  describe '#enabled_dependencies' do
    subject { dump.model_for(clazz).enabled_dependencies.to_a }

    context 'when there is no dependency' do
      let(:clazz) { Organization }

      it { is_expected.to be_empty }
    end

    context 'when there is a simple dependency' do
      let(:clazz) { Company }

      it do
        # binding.pry
        is_expected.to include(
          have_attributes(
            name: :organization,
            models: [dump.model_for(Organization)],
            foreign_key: 'organization_id',
            foreign_type: nil,
            polymorphic?: false,
            soft?: false,
            hard?: true
          )
        )
      end
    end

    context 'when there is a STI dependency' do
      let(:clazz) { User }

      it do
        is_expected.to include(
          have_attributes(
            name: :current_role,
            # models: [dump.model_for(Role)],
            # foreign_key: 'current_role_id',
            # foreign_type: nil,
            # polymorphic?: false,
            soft?: true,
            hard?: false
          )
        )
      end
    end

    context 'when there is a polymorphic dependency' do
      let(:clazz) { Comment }

      it do
        is_expected.to include(
          have_attributes(
            # name: :commentable,
            # models: [],
            foreign_key: 'commentable_id',
            foreign_type: 'commentable_type',
            # polymorphic?: true,
            # soft?: false,
            hard?: true
          )
        )
      end
    end
  end

  describe '#scope' do
    subject { dump.model_for(clazz).scope }

    context 'when there is no dependency' do
      let(:clazz) { Organization }

      context 'when no scope is defined' do
        it { is_expected.to eq(Organization.all) }
      end

      context 'when a scope is defined' do
        before do
          dump.scope(Organization) { order(:id).limit(2) }
        end

        it { is_expected.to eq(Organization.order(:id).limit(2)) }
      end
    end

    context 'when there is a simple dependency' do
      let(:clazz) { Branch }

      context 'when no scope is defined' do
        it { is_expected.to eq(Branch.all) }
      end

      context 'when a scope is defined for the subject' do
        before do
          dump.scope(Branch) { limit(3) }
        end

        it { is_expected.to eq(Branch.limit(3)) }
      end

      context 'when a scope is defined for a dependency' do
        before do
          dump.scope(Organization) { where(id: 1) }
        end

        it do
          is_expected.to eq(
            Branch.where(
              organization: Organization.where(id: 1)
            )
          )
        end
      end

      context 'when a scope is defined for both the subject and a dependency' do
        before do
          dump.config do
            scope(Organization) { where(id: 1) }
            scope(Branch) { where(id: 2) }
          end
        end

        it do
          is_expected.to eq(
            Branch.where(
              id: 2,
              organization: Organization.where(id: 1)
            )
          )
        end
      end
    end

    context 'when there is a STI dependency' do
      let(:clazz) { User }

      before do
        dump.config do
          model(Role).config do
            ignore :user
          end
        end
      end

      context 'when no scope is defined' do
        it { is_expected.to eq(User.all) }
      end

      context 'when a scope is defined for the subject' do
        before do
          dump.scope(User) { limit(3) }
        end

        it { is_expected.to eq(User.limit(3)) }
      end

      context 'when a scope is defined for a dependency' do
        before do
          dump.scope(Role) { where(id: 1) }
        end

        it do
          is_expected.to eq(
            User.where(
              current_role: Role.where(id: 1)
            )
          )
        end
      end

      context 'when a scope is defined for both the subject and a dependency' do
        before do
          dump.config do
            scope(Role) { where(id: 1) }
            scope(User) { where(id: 2) }
          end
        end

        it do
          is_expected.to eq(
            User.where(
              id: 2,
              current_role: Role.where(id: 1)
            )
          )
        end
      end
    end

    context 'when there is a 0-level circular dependency' do
      let(:clazz) { Category }

      context 'when no scope is defined' do
        it { is_expected.to eq(Category.all) }
      end

      context 'when a scope is defined' do
        before do
          dump.scope(Category) { limit(3) }
        end

        it do
          categories = Category.arel_table
          parent_categories = categories.alias(:parent_categories)

          join = categories.join(parent_categories, Arel::Nodes::OuterJoin)
                           .on(parent_categories[:id].eq(categories[:parent_id]))
                           .join_sources

          is_expected.to eq(
            Category.select(
              :id,
              parent_categories[:id].as('parent_id'),
              :label,
              :description
            ).joins(join).limit(3)
          )
        end
      end
    end

    context 'when there is a 1-level circular dependency' do
      context 'when the subject has a hard dependency' do
        let(:clazz) { Role }

        context 'when no scope is defined' do
          it { is_expected.to eq(Role.all) }
        end

        context 'when a scope is defined for the subject' do
          before do
            dump.scope(Role) { limit(3) }
          end

          it { is_expected.to eq(Role.limit(3)) }
        end

        context 'when a scope is defined for a dependency' do
          before do
            dump.scope(User) { where(id: 1) }
          end

          it do
            is_expected.to eq(
              Role.where(
                user: User.where(id: 1)
              )
            )
          end
        end

        context 'when a scope is defined for both the subject and a dependency' do
          before do
            dump.config do
              scope(User) { where(id: 1) }
              scope(Role) { where(id: 2) }
            end
          end

          it do
            is_expected.to eq(
              Role.where(
                id: 2,
                user: User.where(id: 1)
              )
            )
          end
        end
      end

      context 'when the subject has a soft dependency' do
        let(:clazz) { User }

        context 'when no scope is defined' do
          it { is_expected.to eq(User.all) }
        end

        context 'when a scope is defined for the subject' do
          before do
            dump.scope(User) { limit(3) }
          end

          it do
            is_expected.to eq(
              User.select(
                :id,
                :email,
                :name,
                Role.arel_table[:id].as('current_role_id')
              ).left_joins(:current_role).limit(3)
            )
          end
        end

        context 'when a scope is defined for a dependency' do
          before do
            dump.scope(Role) { where(id: 1) }
          end

          it do
            is_expected.to eq(
              User.select(
                :id,
                :email,
                :name,
                Role.arel_table[:id].as('current_role_id')
              ).left_joins(:current_role)
            )
          end
        end

        context 'when a scope is defined for both the subject and a dependency' do
          before do
            dump.config do
              scope(User) { where(id: 2) }
              scope(Role) { where(id: 1) }
            end
          end

          it do
            is_expected.to eq(
              User.select(
                :id,
                :email,
                :name,
                Role.arel_table[:id].as('current_role_id')
              ).left_joins(:current_role).where(id: 2)
            )
          end
        end
      end

      context 'when there is only hard dependencies' do
        class FixCurrentRoleOfUser < ActiveRecord::Migration[5.0]
          def up
            drop_table :users

            create_table :users do |t|
              t.string :email, :name
              t.integer :current_role_id, null: false
            end
          end

          def down
            drop_table :users

            create_table :users do |t|
              t.string :email, :name
              t.integer :current_role_id
            end
          end
        end

        let(:clazz) { Role }

        before do
          FixCurrentRoleOfUser.new.up
          User.reset_column_information
        end

        after do
          FixCurrentRoleOfUser.new.down
          User.reset_column_information
        end

        it { expect { subject }.to raise_error(Export::CircularDependencyError) }
      end
    end

    context 'when there is a 2+-level circular dependency' do
      context 'when the subject has a hard dependency' do
        let(:clazz) { Order }

        before do
          dump.config do
            model(Company).ignore :organization
          end
        end

        context 'when no scope is defined' do
          it { is_expected.to eq(Order.all) }
        end

        context 'when a scope is defined for the subject' do
          before do
            dump.scope(Order) { limit(3) }
          end

          it { is_expected.to eq(Order.limit(3)) }
        end

        context 'when a scope is defined for a dependency' do
          before do
            dump.scope(Contact) { where(id: 1) }
            dump.scope(User) { where(id: 2) }
          end

          it do
            is_expected.to eq(
              Order.where(
                user: User.where(id: 2),
                contact: Contact.where(id: 1)
              )
            )
          end
        end

        context 'when a scope is defined for both the subject and a dependency' do
          before do
            dump.config do
              scope(Contact) { where(id: 1) }
              scope(Company) { where(id: 3) }
              scope(Order) { where(id: 2) }
            end
          end

          it do
            is_expected.to eq(
              Order.where(
                id: 2,
                contact: Contact.where(
                  id: 1,
                  company: Company.where(id: 3)
                )
              )
            )
          end
        end
      end

      context 'when the subject has a soft dependency' do
        let(:clazz) { Company }

        before do
          dump.config do
            model(Order).ignore :user
            model(Company).ignore :organization
          end
        end

        context 'when no scope is defined' do
          it { is_expected.to eq(Company.all) }
        end

        context 'when a scope is defined for the subject' do
          before do
            dump.scope(Company) { limit(3) }
          end

          it do
            is_expected.to eq(
              Company.select(
                :id,
                :organization_id,
                :name,
                Order.arel_table[:id].as('last_order_id')
              ).left_joins(:last_order).limit(3)
            )
          end
        end

        context 'when a scope is defined for a dependency' do
          before do
            dump.scope(Order) { where(id: 1) }
          end

          it do
            is_expected.to eq(
              Company.select(
                :id,
                :organization_id,
                :name,
                Order.arel_table[:id].as('last_order_id')
              ).left_joins(:last_order)
            )
          end
        end

        context 'when a scope is defined for both the subject and a dependency' do
          before do
            dump.config do
              scope(Contact) { where(id: 1) }
              scope(Company) { where(id: 3) }
              scope(Order) { where(id: 2) }
            end
          end

          it do
            is_expected.to eq(
              Company.select(
                :id,
                :organization_id,
                :name,
                Order.arel_table[:id].as('last_order_id')
              ).left_joins(:last_order).where(id: 3)
            )
          end
        end
      end
    end

    context 'when there is a polymorphic dependency' do
      let(:clazz) { Comment }

      before do
        Admin.create(
          user: User.create(
            email: FFaker::Internet.email,
            name: FFaker::Name.name
          )
        )
        Organization.create name: FFaker::Name.name
        Organization.create name: FFaker::Name.name
        Product.create name: FFaker::Product.name
        Product.create name: FFaker::Product.name

        Comment.create description: FFaker::Lorem.paragraph,
                       commentable: Organization.random,
                       role: Role.first
        Comment.create description: FFaker::Lorem.paragraph,
                       commentable: Product.random,
                       role: Role.first
        Comment.create description: FFaker::Lorem.paragraph,
                       commentable: Product.random,
                       role: Role.first
      end

      context 'when the subject has a hard dependency' do
        context 'when no scope is defined' do
          it { is_expected.to eq(Comment.all) }
        end

        context 'when a scope is defined for the subject' do
          before do
            dump.scope(Comment) { limit(3) }
          end

          it { is_expected.to eq(Comment.limit(3)) }
        end

        context 'when a scope is defined for a dependency' do
          before do
            dump.scope(Organization) { where(id: 1) }
            dump.scope(Product) { where(id: 2) }
          end

          it do
            table = Comment.arel_table
            organizations_query = Organization.where(id: 1).select(:id)
            products_query = Product.where(id: 2).select(:id)

            is_expected.to eq(
              Comment.where(
                Arel::Nodes::Grouping.new(
                  Arel::Nodes::Grouping.new(
                    table[:commentable_type].eq('Organization').and(table[:commentable_id].in(organizations_query.arel))
                  ).or(
                    Arel::Nodes::Grouping.new(
                      table[:commentable_type].eq('Product').and(table[:commentable_id].in(products_query.arel))
                    )
                  )
                )
              ).tap { |q| q.where_clause.binds.push(*organizations_query.bound_attributes, *products_query.bound_attributes) }
            )
          end
        end

        # context 'when a scope is defined for both the subject and a dependency' do
        #   before do
        #     dump.config do
        #       scope(Contact) { where(id: 1) }
        #       scope(Company) { where(id: 3) }
        #       scope(Order) { where(id: 2) }
        #     end
        #   end

        #   it do
        #     is_expected.to eq(
        #       Order.where(
        #         id: 2,
        #         contact: Contact.where(
        #           id: 1,
        #           company: Company.where(id: 3)
        #         )
        #       )
        #     )
        #   end
        # end
      end
    end
  end
end
