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
        it { is_expected.to query(Organization.all) }
      end

      context 'when a scope is defined' do
        before do
          dump.scope(Organization) { order(:id).limit(2) }
        end

        it { is_expected.to query(Organization.order(:id).limit(2)) }
      end
    end

    context 'when there is a simple dependency' do
      let(:clazz) { Branch }

      context 'when no scope is defined' do
        it { is_expected.to query(Branch.all) }
      end

      context 'when a scope is defined for the subject' do
        before do
          dump.scope(Branch) { limit(3) }
        end

        it { is_expected.to query(Branch.limit(3)) }
      end

      context 'when a scope is defined for a dependency' do
        before do
          dump.scope(Organization) { where(id: 1) }
        end

        it do
          is_expected.to query(
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
          is_expected.to query(
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
        it { is_expected.to query(User.all) }
      end

      context 'when a scope is defined for the subject' do
        before do
          dump.scope(User) { limit(3) }
        end

        it { is_expected.to query(User.limit(3)) }
      end

      context 'when a scope is defined for a dependency' do
        before do
          dump.scope(Role) { where(id: 1) }
        end

        it do
          is_expected.to query(
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
          is_expected.to query(
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
        it { is_expected.to query(Category.all) }
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

          is_expected.to query(
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
          it { is_expected.to query(Role.all) }
        end

        context 'when a scope is defined for the subject' do
          before do
            dump.scope(Role) { limit(3) }
          end

          it { is_expected.to query(Role.limit(3)) }
        end

        context 'when a scope is defined for a dependency' do
          before do
            dump.scope(User) { where(id: 1) }
          end

          it do
            is_expected.to query(
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
            is_expected.to query(
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
          it { is_expected.to query(User.all) }
        end

        context 'when a scope is defined for the subject' do
          before do
            dump.scope(User) { limit(3) }
          end

          it do
            is_expected.to query(
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
            is_expected.to query(
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
            is_expected.to query(
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

    context 'when there is a 2-plus-level circular dependency' do
      context 'when the subject has a hard dependency' do
        let(:clazz) { Order }

        before do
          dump.config do
            model(Company).ignore :organization
          end
        end

        context 'when no scope is defined' do
          it { is_expected.to query(Order.all) }
        end

        context 'when a scope is defined for the subject' do
          before do
            dump.scope(Order) { limit(3) }
          end

          it { is_expected.to query(Order.limit(3)) }
        end

        context 'when a scope is defined for a dependency' do
          before do
            dump.scope(Contact) { where(id: 1) }
            dump.scope(User) { where(id: 2) }
          end

          it do
            is_expected.to query(
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
            is_expected.to query(
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
          it { is_expected.to query(Company.all) }
        end

        context 'when a scope is defined for the subject' do
          before do
            dump.scope(Company) { limit(3) }
          end

          it do
            is_expected.to query(
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
            is_expected.to query(
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
            is_expected.to query(
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

      context 'when there is a simple dependency' do
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

        context 'when no scope is defined' do
          it { is_expected.to query(Comment.all) }
        end

        context 'when a scope is defined for the subject' do
          before do
            dump.scope(Comment) { limit(3) }
          end

          it { is_expected.to query(Comment.limit(3)) }
        end

        context 'when a scope is defined for a dependency' do
          before do
            dump.config do
              scope(Organization) { where(id: 1) }
              scope(Product) { where(id: 2) }
            end
          end

          it do
            table = Comment.arel_table
            organizations_query = Organization.where(id: 1).select(:id)
            products_query = Product.where(id: 2).select(:id)

            is_expected.to query(
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
              ).tap { |q| q.where_clause.binds.concat(organizations_query.bound_attributes).concat(products_query.bound_attributes) }
            )
          end
        end

        context 'when a scope is defined for both the subject and a dependency' do
          before do
            dump.config do
              scope(Organization) { where(id: 1) }
              scope(Comment) { where(id: 2) }
            end
          end

          it do
            table = Comment.arel_table
            organizations_query = Organization.where(id: 1).select(:id)

            is_expected.to query(
              Comment.where(id: 2)
                     .where(
                       Arel::Nodes::Grouping.new(
                         Arel::Nodes::Grouping.new(
                           table[:commentable_type].eq('Organization').and(table[:commentable_id].in(organizations_query.arel))
                         )
                       )
                     ).tap { |q| q.where_clause.binds.concat(organizations_query.bound_attributes) }
            )
          end
        end
      end

      context 'when there is a 0-level circular dependency' do
        before do
          Admin.create(
            user: User.create(
              email: FFaker::Internet.email,
              name: FFaker::Name.name
            )
          )
          Organization.create name: FFaker::Name.name
          Comment.create description: FFaker::Lorem.paragraph,
                         commentable: Organization.first,
                         role: Role.first
          Comment.create description: FFaker::Lorem.paragraph,
                         commentable: Comment.first,
                         role: Role.first
        end

        context 'when no scope is defined' do
          it { is_expected.to query(Comment.all) }
        end

        context 'when a scope is defined for the subject' do
          before do
            dump.scope(Comment) { limit(3) }
          end

          xit do
            comments = Comment.arel_table
            commentable_comments = comments.alias(:commentable_comments)

            join = comments.join(commentable_comments, Arel::Nodes::OuterJoin)
                           .on(commentable_comments[:id].eq(comments[:commentable_id]))
                           .join_sources

            is_expected.to eq(
              Comment.select(
                :id,
                :description,
                :role,
                commentable_comments[:commentable_id].as('commentable_id'),
                commentable_comments[:commentable_type].as('commentable_type')
              ).joins(join).limit(3)
            )
          end
        end
      end

      context 'when there is a 1-level circular dependency' do
        context 'when the subject has a hard dependency' do
          class AddLastCommentToOrder < ActiveRecord::Migration[5.0]
            def up
              drop_table :orders

              create_table :orders do |t|
                t.references :user, null: false
                t.references :contact, null: true
                t.references :last_comment, null: true
                t.string :status
              end
            end

            def down
              drop_table :orders

              create_table :orders do |t|
                t.references :user, null: false
                t.references :contact, null: false
                t.string :status
              end
            end
          end

          before do
            AddLastCommentToOrder.new.up
            Order.reset_column_information

            User.create email: FFaker::Internet.email,
                        name: FFaker::Name.name
            Admin.create user: User.first
            Order.create user: User.first
            Comment.create description: FFaker::Lorem.paragraph,
                           commentable: Order.first,
                           role: Role.first

            Order.first.update last_comment_id: Comment.first.id
          end

          after do
            AddLastCommentToOrder.new.down
            Order.reset_column_information
          end

          context 'when no scope is defined' do
            it { is_expected.to query(Comment.all) }
          end

          context 'when a scope is defined for the subject' do
            before do
              dump.scope(Comment) { limit(3) }
            end

            it { is_expected.to query(Comment.limit(3)) }
          end

          context 'when a scope is defined for a dependency' do
            before do
              dump.scope(Order) { where(id: 1) }
            end

            it do
              table = Comment.arel_table
              orders_query = Order.where(id: 1).select(:id)

              is_expected.to query(
                Comment.where(
                  Arel::Nodes::Grouping.new(
                    Arel::Nodes::Grouping.new(
                      table[:commentable_type].eq('Order').and(table[:commentable_id].in(orders_query.arel))
                    )
                  )
                ).tap { |q| q.where_clause.binds.concat(orders_query.bound_attributes) }
              )
            end
          end

          context 'when a scope is defined for both the subject and a dependency' do
            before do
              dump.config do
                scope(Order) { where(id: 1) }
                scope(Comment) { where(id: 2) }
              end
            end

            it do
              table = Comment.arel_table
              orders_query = Order.where(id: 1).select(:id)

              is_expected.to query(
                Comment.where(id: 2)
                       .where(
                         Arel::Nodes::Grouping.new(
                           Arel::Nodes::Grouping.new(
                             table[:commentable_type].eq('Order').and(table[:commentable_id].in(orders_query.arel))
                           )
                         )
                       ).tap { |q| q.where_clause.binds.concat(orders_query.bound_attributes) }
              )
            end
          end
        end

        context 'when the subject has a soft dependency' do
          class AddLastRequiredCommentToOrder < ActiveRecord::Migration[5.0]
            def up
              drop_table :orders
              drop_table :comments

              create_table :orders do |t|
                t.references :user, null: false
                t.references :contact, null: true
                t.references :last_comment, null: false
                t.string :status
              end

              create_table :comments do |t|
                t.string :description
                t.references :role, null: false
                t.references :commentable, polymorphic: true, index: true, null: true
              end
            end

            def down
              drop_table :orders
              drop_table :comments

              create_table :orders do |t|
                t.references :user, null: false
                t.references :contact, null: false
                t.string :status
              end

              create_table :comments do |t|
                t.string :description
                t.references :role, null: false
                t.references :commentable, polymorphic: true, index: true, null: false
              end
            end
          end

          before do
            AddLastRequiredCommentToOrder.new.up
            Order.reset_column_information
            Comment.reset_column_information

            Order.class_eval do
              belongs_to :last_comment, class_name: 'Comment'
            end

            User.create email: FFaker::Internet.email,
                        name: FFaker::Name.name
            Admin.create user: User.first
            Comment.create description: FFaker::Lorem.paragraph,
                           role: Role.first
            Order.create user: User.first,
                         last_comment: Comment.first

            Comment.first.update commentable_type: 'Order',
                                 commentable_id: Order.first.id
          end

          after do
            AddLastRequiredCommentToOrder.new.down
            Order.reset_column_information
            Comment.reset_column_information
          end

          context 'when no scope is defined' do
            it { is_expected.to query(Comment.all) }
          end

          context 'when a scope is defined for the subject' do
            before do
              dump.scope(Comment) { limit(3) }
            end

            it do
              orders_query = Order.select(
                Arel::Nodes::As.new(Arel::Nodes::Quoted.new('Order'), Arel::Nodes::SqlLiteral.new('type')),
                Order.arel_table[:id].as('id')
              )
              commentables = Arel::Table.new(:commentables)
              commentables_content = Arel::Nodes::As.new(commentables, orders_query.arel)

              comments = Comment.arel_table.from
              comments.take(Arel::Nodes::BindParam.new)
              comments.projections = [
                comments.source.left[:id],
                comments.source.left[:description],
                comments.source.left[:role_id],
                commentables[:type].as('commentable_type'),
                commentables[:id].as('commentable_id')
              ]
              comments.join(commentables, Arel::Nodes::OuterJoin)
                      .on(commentables[:type].eq(comments.source.left[:commentable_type]).and(commentables[:id].eq(comments.source.left[:commentable_id])))
                      .with(commentables_content)

              is_expected.to query(comments).and_bind([3])
            end
          end

        #   context 'when a scope is defined for a dependency' do
        #     before do
        #       dump.scope(Role) { where(id: 1) }
        #     end

        #     it do
        #       is_expected.to eq(
        #         User.select(
        #           :id,
        #           :email,
        #           :name,
        #           Role.arel_table[:id].as('current_role_id')
        #         ).left_joins(:current_role)
        #       )
        #     end
        #   end

        #   context 'when a scope is defined for both the subject and a dependency' do
        #     before do
        #       dump.config do
        #         scope(User) { where(id: 2) }
        #         scope(Role) { where(id: 1) }
        #       end
        #     end

        #     it do
        #       is_expected.to eq(
        #         User.select(
        #           :id,
        #           :email,
        #           :name,
        #           Role.arel_table[:id].as('current_role_id')
        #         ).left_joins(:current_role).where(id: 2)
        #       )
        #     end
        #   end
        end
      end
    end
  end
end
