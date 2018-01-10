require 'spec_helper'

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
            models: [dump.model_for(Role)],
            foreign_key: 'current_role_id',
            foreign_type: nil,
            polymorphic?: false,
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
          categories_query = Category.select(
            Category.arel_table[:id].as('id')
          ).limit(3)
          parents = Arel::Table.new(:parents)
          parents_content = Arel::Nodes::As.new(parents, Arel::Nodes::Grouping.new(categories_query.ast))

          categories = Category.arel_table.from
          categories.take(Arel::Nodes::BindParam.new)
          categories.projections = [
            categories.source.left[:id],
            parents[:id].as('parent_id'),
            categories.source.left[:label],
            categories.source.left[:description]
          ]
          categories.join(parents, Arel::Nodes::OuterJoin)
                    .on(parents[:id].eq(categories.source.left[:parent_id]))
                    .with(parents_content)

          is_expected.to query(categories).and_bind([3, 3])
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
            roles_users = User.arel_table.from
            roles_users.take(Arel::Nodes::BindParam.new)
            roles_users.projections = [roles_users.source.left[:id]]

            roles = Role.arel_table.from
            roles.projections = [roles.source.left[:id].as('id')]
            roles.where(roles.source.left[:user_id].in(roles_users))

            current_roles = Arel::Table.new(:current_roles)
            current_roles_content = Arel::Nodes::As.new(current_roles, Arel::Nodes::Grouping.new(roles.ast))

            users = User.arel_table.from
            users.take(Arel::Nodes::BindParam.new)
            users.projections = [
              users.source.left[:id],
              users.source.left[:email],
              users.source.left[:name],
              current_roles[:id].as('current_role_id')
            ]
            users.join(current_roles, Arel::Nodes::OuterJoin)
                 .on(current_roles[:id].eq(users.source.left[:current_role_id]))
                 .with(current_roles_content)

            is_expected.to query(users).and_bind([3, 3])
          end
        end

        context 'when a scope is defined for a dependency' do
          before do
            dump.scope(Role) { where(id: 1) }
          end

          it do
            roles_query = Role.select(
              Role.arel_table[:id].as('id')
            ).where(id: 1)
            current_roles = Arel::Table.new(:current_roles)
            current_roles_content = Arel::Nodes::As.new(current_roles, Arel::Nodes::Grouping.new(roles_query.ast))

            users = User.arel_table.from
            users.projections = [
              users.source.left[:id],
              users.source.left[:email],
              users.source.left[:name],
              current_roles[:id].as('current_role_id')
            ]
            users.join(current_roles, Arel::Nodes::OuterJoin)
                 .on(current_roles[:id].eq(users.source.left[:current_role_id]))
                 .with(current_roles_content)

            is_expected.to query(users).and_bind([1])
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
            roles_users = User.arel_table.from
            roles_users.where(roles_users.source.left[:id].eq(Arel::Nodes::BindParam.new))
            roles_users.projections = [roles_users.source.left[:id]]

            roles = Role.arel_table.from
            roles.projections = [roles.source.left[:id].as('id')]
            roles.where(roles.source.left[:id].eq(Arel::Nodes::BindParam.new))
            roles.where(roles.source.left[:user_id].in(roles_users))

            current_roles = Arel::Table.new(:current_roles)
            current_roles_content = Arel::Nodes::As.new(current_roles, Arel::Nodes::Grouping.new(roles.ast))

            users = User.arel_table.from
            users.projections = [
              users.source.left[:id],
              users.source.left[:email],
              users.source.left[:name],
              current_roles[:id].as('current_role_id')
            ]
            users.where(users.source.left[:id].eq(Arel::Nodes::BindParam.new))
            users.join(current_roles, Arel::Nodes::OuterJoin)
                 .on(current_roles[:id].eq(users.source.left[:current_role_id]))
                 .with(current_roles_content)

            is_expected.to query(users).and_bind([1, 2, 2])
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
            orders_companies = Company.arel_table.from
            orders_companies.take(Arel::Nodes::BindParam.new)
            orders_companies.projections = [orders_companies.source.left[:id]]

            orders_contacts = Contact.arel_table.from
            orders_contacts.projections = [orders_contacts.source.left[:id]]
            orders_contacts.where(orders_contacts.source.left[:company_id].in(orders_companies))

            orders = Order.arel_table.from
            orders.projections = [orders.source.left[:id].as('id')]
            orders.where(orders.source.left[:contact_id].in(orders_contacts))

            last_orders = Arel::Table.new(:last_orders)
            last_orders_content = Arel::Nodes::As.new(last_orders, Arel::Nodes::Grouping.new(orders.ast))

            companies = Company.arel_table.from
            companies.projections = [
              companies.source.left[:id],
              companies.source.left[:organization_id],
              companies.source.left[:name],
              last_orders[:id].as('last_order_id')
            ]
            companies.take(Arel::Nodes::BindParam.new)
            companies.join(last_orders, Arel::Nodes::OuterJoin)
                     .on(last_orders[:id].eq(companies.source.left[:last_order_id]))
                     .with(last_orders_content)

            is_expected.to query(companies).and_bind([3, 3])
          end
        end

        context 'when a scope is defined for a dependency' do
          before do
            dump.scope(Order) { where(id: 1) }
          end

          it do
            orders = Order.arel_table.from
            orders.projections = [orders.source.left[:id].as('id')]
            orders.where(orders.source.left[:id].eq(Arel::Nodes::BindParam.new))

            last_orders = Arel::Table.new(:last_orders)
            last_orders_content = Arel::Nodes::As.new(last_orders, Arel::Nodes::Grouping.new(orders.ast))

            companies = Company.arel_table.from
            companies.projections = [
              companies.source.left[:id],
              companies.source.left[:organization_id],
              companies.source.left[:name],
              last_orders[:id].as('last_order_id')
            ]
            companies.join(last_orders, Arel::Nodes::OuterJoin)
                     .on(last_orders[:id].eq(companies.source.left[:last_order_id]))
                     .with(last_orders_content)

            is_expected.to query(companies).and_bind([1])
          end
        end

        context 'when a scope is defined for both the subject and a dependency' do
          before do
            dump.config do
              scope(Contact) { where(id: 1) }
              scope(Company) { where(id: 3) }
              scope(Order) { where(id: [1, 2]) }
            end
          end

          it do
            orders_companies = Company.arel_table.from
            orders_companies.where(orders_companies.source.left[:id].eq(Arel::Nodes::BindParam.new))
            orders_companies.projections = [orders_companies.source.left[:id]]

            orders_contacts = Contact.arel_table.from
            orders_contacts.projections = [orders_contacts.source.left[:id]]
            orders_contacts.where(orders_contacts.source.left[:id].eq(Arel::Nodes::BindParam.new))
            orders_contacts.where(orders_contacts.source.left[:company_id].in(orders_companies))

            orders = Order.arel_table.from
            orders.projections = [orders.source.left[:id].as('id')]
            orders.where(orders.source.left[:id].in([1, 2]))
            orders.where(orders.source.left[:contact_id].in(orders_contacts))

            last_orders = Arel::Table.new(:last_orders)
            last_orders_content = Arel::Nodes::As.new(last_orders, Arel::Nodes::Grouping.new(orders.ast))

            companies = Company.arel_table.from
            companies.projections = [
              companies.source.left[:id],
              companies.source.left[:organization_id],
              companies.source.left[:name],
              last_orders[:id].as('last_order_id')
            ]
            companies.where(companies.source.left[:id].eq(Arel::Nodes::BindParam.new))
            companies.join(last_orders, Arel::Nodes::OuterJoin)
                     .on(last_orders[:id].eq(companies.source.left[:last_order_id]))
                     .with(last_orders_content)

            is_expected.to query(companies).and_bind([1, 3, 3])
          end

          context 'when there is multiple soft dependencies' do
            class AddFirstOrderToCompany < ActiveRecord::Migration[5.0]
              def up
                drop_table :companies

                create_table :companies do |t|
                  t.references :organization, null: false
                  t.string :name
                  t.references :first_order, null: true
                  t.references :last_order, null: true
                end
              end

              def down
                drop_table :companies

                create_table :companies do |t|
                  t.references :organization, null: false
                  t.string :name
                  t.references :last_order, null: true
                end
              end
            end

            before do
              AddFirstOrderToCompany.new.up
              Company.reset_column_information

              Company.class_eval do
                belongs_to :first_order, class_name: 'Order'
              end

              dump.reload_models
            end

            it do
              orders_companies = Company.arel_table.from
              orders_companies.where(orders_companies.source.left[:id].eq(Arel::Nodes::BindParam.new))
              orders_companies.projections = [orders_companies.source.left[:id]]

              orders_contacts = Contact.arel_table.from
              orders_contacts.projections = [orders_contacts.source.left[:id]]
              orders_contacts.where(orders_contacts.source.left[:id].eq(Arel::Nodes::BindParam.new))
              orders_contacts.where(orders_contacts.source.left[:company_id].in(orders_companies))

              orders = Order.arel_table.from
              orders.projections = [orders.source.left[:id].as('id')]
              orders.where(orders.source.left[:id].in([1, 2]))
              orders.where(orders.source.left[:contact_id].in(orders_contacts))

              last_orders = Arel::Table.new(:last_orders)
              last_orders_content = Arel::Nodes::As.new(last_orders, Arel::Nodes::Grouping.new(orders.ast))

              first_orders = Arel::Table.new(:first_orders)
              first_orders_content = Arel::Nodes::As.new(first_orders, Arel::Nodes::Grouping.new(orders.ast))

              companies = Company.arel_table.from
              companies.projections = [
                companies.source.left[:id],
                companies.source.left[:organization_id],
                companies.source.left[:name],
                first_orders[:id].as('first_order_id'),
                last_orders[:id].as('last_order_id')
              ]
              companies.where(companies.source.left[:id].eq(Arel::Nodes::BindParam.new))
              companies.join(last_orders, Arel::Nodes::OuterJoin)
                       .on(last_orders[:id].eq(companies.source.left[:last_order_id]))
              companies.join(first_orders, Arel::Nodes::OuterJoin)
                       .on(first_orders[:id].eq(companies.source.left[:first_order_id]))
              companies.with(first_orders_content, last_orders_content)

              is_expected.to query(companies).and_bind([1, 3, 1, 3, 3])
            end
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
              model(Branch) do
                scope_by { where(id: 3) }
                ignore(:organization)
              end
            end

            Branch.create code: FFaker::Internet.email,
                          organization: Organization.first

            Comment.create description: FFaker::Lorem.paragraph,
                           commentable: Branch.first,
                           role: Role.first
          end

          it do
            organizations = Organization.arel_table.from
            organizations.projections = [
              Arel::Nodes::As.new(Arel::Nodes::Quoted.new('Organization'), Arel::Nodes::SqlLiteral.new('type')),
              organizations.source.left[:id].as('id')
            ]
            organizations.where(organizations.source.left[:id].eq(Arel::Nodes::BindParam.new))

            products = Product.arel_table.from
            products.projections = [
              Arel::Nodes::As.new(Arel::Nodes::Quoted.new('Product'), Arel::Nodes::SqlLiteral.new('type')),
              products.source.left[:id].as('id')
            ]
            products.where(products.source.left[:id].eq(Arel::Nodes::BindParam.new))

            branches = Branch.arel_table.from
            branches.projections = [
              Arel::Nodes::As.new(Arel::Nodes::Quoted.new('Branch'), Arel::Nodes::SqlLiteral.new('type')),
              branches.source.left[:id].as('id')
            ]
            branches.where(branches.source.left[:id].eq(Arel::Nodes::BindParam.new))

            commentables = Arel::Table.new(:commentables).from
            commentables.projections = [
              commentables.source.left[:type],
              commentables.source.left[:id]
            ]
            commentables_content = Arel::Nodes::As.new(commentables.source.left, Arel::Nodes::Grouping.new(branches.union_all(organizations).union_all(products)))

            comments = Comment.arel_table.from
            comments.project(comments.source.left[Arel::Nodes::SqlLiteral.new('*')])
            comments.where(Arel::Nodes::Grouping.new([comments.source.left[:commentable_type], comments.source.left[:commentable_id]]).in(commentables))
                    .with(commentables_content)

            is_expected.to query(comments).and_bind([3, 1, 2])
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
            organizations = Organization.arel_table.from
            organizations.projections = [
              Arel::Nodes::As.new(Arel::Nodes::Quoted.new('Organization'), Arel::Nodes::SqlLiteral.new('type')),
              organizations.source.left[:id].as('id')
            ]
            organizations.where(organizations.source.left[:id].eq(Arel::Nodes::BindParam.new))

            commentables = Arel::Table.new(:commentables).from
            commentables.projections = [
              commentables.source.left[:type],
              commentables.source.left[:id]
            ]
            commentables_content = Arel::Nodes::As.new(commentables.source.left, Arel::Nodes::Grouping.new(organizations.ast))

            comments = Comment.arel_table.from
            comments.project(comments.source.left[Arel::Nodes::SqlLiteral.new('*')])
            comments.where(comments.source.left[:id].eq(Arel::Nodes::BindParam.new))
            comments.where(Arel::Nodes::Grouping.new([comments.source.left[:commentable_type], comments.source.left[:commentable_id]]).in(commentables))
                    .with(commentables_content)

            is_expected.to query(comments).and_bind([1, 2])
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
            dump.scope(Comment) { where(id: 2) }
          end

          it { expect { subject }.to raise_error(Export::CircularDependencyError) }
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
              orders = Order.arel_table.from
              orders.projections = [
                Arel::Nodes::As.new(Arel::Nodes::Quoted.new('Order'), Arel::Nodes::SqlLiteral.new('type')),
                orders.source.left[:id].as('id')
              ]
              orders.where(orders.source.left[:id].eq(Arel::Nodes::BindParam.new))

              commentables = Arel::Table.new(:commentables).from
              commentables.projections = [
                commentables.source.left[:type],
                commentables.source.left[:id]
              ]
              commentables_content = Arel::Nodes::As.new(commentables.source.left, Arel::Nodes::Grouping.new(orders.ast))

              comments = Comment.arel_table.from
              comments.project(comments.source.left[Arel::Nodes::SqlLiteral.new('*')])
              comments.where(Arel::Nodes::Grouping.new([comments.source.left[:commentable_type], comments.source.left[:commentable_id]]).in(commentables))
                      .with(commentables_content)

              is_expected.to query(comments).and_bind([1])
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
              orders = Order.arel_table.from
              orders.projections = [
                Arel::Nodes::As.new(Arel::Nodes::Quoted.new('Order'), Arel::Nodes::SqlLiteral.new('type')),
                orders.source.left[:id].as('id')
              ]
              orders.where(orders.source.left[:id].eq(Arel::Nodes::BindParam.new))

              commentables = Arel::Table.new(:commentables).from
              commentables.projections = [
                commentables.source.left[:type],
                commentables.source.left[:id]
              ]
              commentables_content = Arel::Nodes::As.new(commentables.source.left, Arel::Nodes::Grouping.new(orders.ast))

              comments = Comment.arel_table.from
              comments.project(comments.source.left[Arel::Nodes::SqlLiteral.new('*')])
              comments.where(comments.source.left[:id].eq(Arel::Nodes::BindParam.new))
              comments.where(Arel::Nodes::Grouping.new([comments.source.left[:commentable_type], comments.source.left[:commentable_id]]).in(commentables))
                      .with(commentables_content)

              is_expected.to query(comments).and_bind([1, 2])
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
              orders_comments = Comment.arel_table.from
              orders_comments.projections = [orders_comments.source.left[:id]]
              orders_comments.take(Arel::Nodes::BindParam.new)

              orders = Order.arel_table.from
              orders.projections = [
                Arel::Nodes::As.new(Arel::Nodes::Quoted.new('Order'), Arel::Nodes::SqlLiteral.new('type')),
                orders.source.left[:id].as('id')
              ]
              orders.where(orders.source.left[:last_comment_id].in(orders_comments))

              commentables = Arel::Table.new(:commentables)
              commentables_content = Arel::Nodes::As.new(commentables, Arel::Nodes::Grouping.new(orders.ast))

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

              is_expected.to query(comments).and_bind([3, 3])
            end
          end

          context 'when a scope is defined for a dependency' do
            before do
              dump.scope(Order) { where(id: 1) }
            end

            it do
              orders = Order.arel_table.from
              orders.projections = [
                Arel::Nodes::As.new(Arel::Nodes::Quoted.new('Order'), Arel::Nodes::SqlLiteral.new('type')),
                orders.source.left[:id].as('id')
              ]
              orders.where(orders.source.left[:id].eq(Arel::Nodes::BindParam.new))

              commentables = Arel::Table.new(:commentables)
              commentables_content = Arel::Nodes::As.new(commentables, Arel::Nodes::Grouping.new(orders.ast))

              comments = Comment.arel_table.from
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

              is_expected.to query(comments).and_bind([1])
            end
          end

          context 'when a scope is defined for both the subject and a dependency' do
            before do
              Comment.create description: FFaker::Lorem.paragraph,
                             commentable: User.first,
                             role: Role.first

              dump.config do
                scope(Order) { where(id: 1) }
                scope(User) { limit(3) }
                model(Comment) do
                  ignore(:role)
                  scope_by { where(id: 2) }
                end
              end
            end

            it do
              users = User.arel_table.from
              users.projections = [users.source.left[:id]]
              users.take(Arel::Nodes::BindParam.new)

              polymorphic_users = users.dup
              polymorphic_users.projections = [
                Arel::Nodes::As.new(Arel::Nodes::Quoted.new('User'), Arel::Nodes::SqlLiteral.new('type')),
                polymorphic_users.source.left[:id].as('id')
              ]

              hard_commentables = Arel::Table.new(:hard_commentables).from
              hard_commentables.projections = [
                hard_commentables.source.left[:type],
                hard_commentables.source.left[:id]
              ]
              hard_commentables_content = Arel::Nodes::As.new(hard_commentables.source.left, Arel::Nodes::Grouping.new(polymorphic_users.ast))

              orders_comments = Comment.arel_table.from
              orders_comments.projections = [orders_comments.source.left[:id]]
              orders_comments.where(orders_comments.source.left[:id].eq(Arel::Nodes::BindParam.new))
              orders_comments.where(Arel::Nodes::Grouping.new([orders_comments.source.left[:commentable_type], orders_comments.source.left[:commentable_id]]).in(hard_commentables))
              orders_comments.with(hard_commentables_content)

              orders = Order.arel_table.from
              orders.projections = [
                Arel::Nodes::As.new(Arel::Nodes::Quoted.new('Order'), Arel::Nodes::SqlLiteral.new('type')),
                orders.source.left[:id].as('id')
              ]
              orders.where(orders.source.left[:id].eq(Arel::Nodes::BindParam.new))
              orders.where(orders.source.left[:user_id].in(users))
              orders.where(orders.source.left[:last_comment_id].in(orders_comments))

              soft_commentables = Arel::Table.new(:soft_commentables)
              soft_commentables_content = Arel::Nodes::As.new(soft_commentables, Arel::Nodes::Grouping.new(orders.union_all(polymorphic_users)))

              comments = Comment.arel_table.from
              comments.projections = [
                comments.source.left[:id],
                comments.source.left[:description],
                comments.source.left[:role_id],
                soft_commentables[:type].as('commentable_type'),
                soft_commentables[:id].as('commentable_id')
              ]
              comments.where(comments.source.left[:id].eq(Arel::Nodes::BindParam.new))
              comments.where(Arel::Nodes::Grouping.new([comments.source.left[:commentable_type], comments.source.left[:commentable_id]]).in(hard_commentables))
              comments.join(soft_commentables, Arel::Nodes::OuterJoin)
                      .on(soft_commentables[:type].eq(comments.source.left[:commentable_type]).and(soft_commentables[:id].eq(comments.source.left[:commentable_id])))
                      .prepend_with(hard_commentables_content)
                      .prepend_with(soft_commentables_content)

              is_expected.to query(comments).and_bind([1, 3, 3, 2, 3, 3, 2])
            end
          end
        end
      end
    end
  end
end
