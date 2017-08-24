require 'spec_helper'

describe Export::DependencyTree do

  include_examples 'database setup'

  let(:clazz) { User }
  subject { described_class.new clazz }

  context "#add_dependency" do
    let(:dependency) { User.reflections.values.first }
    before { subject.add_dependency(dependency) }
    specify do
      expect(subject.dependencies.length).to eq(1)
      expect(subject.dependencies.keys).to eq(%w(User#user_id))
    end
  end

  context "#cyclic?" do
    let(:clazz) { User }

    context 'same class' do
      let(:other_dep) { described_class.new(clazz) }

      specify "recursive call to the same class" do
        expect(subject.cyclic?(other_dep)).to be_truthy
      end
    end

    context "with multiple dependencies" do
      let(:clazz) { Comment }
      let(:dependent) { subject.dependencies.values.first }

      specify do
        expect(dependent.cyclic?(described_class.new(clazz))).to be_truthy
      end
    end
  end

  context "#add_dependency" do
    specify do
      expect(subject.dependencies).to be_a(Hash)
      expect(subject.dependencies.values).to all(be_a(described_class))
    end

    context 'include model dependencies' do
      specify do
        expect(subject.dependencies).to be_a(Hash)
        expect(subject.dependencies.length).to eq(1)
        name, dependency = subject.dependencies.first
        expect(name).to eq("User#current_role_id")
        expect(dependency).to be_a(described_class)
      end
    end

    context 'include polymorphic dependencies' do
      let(:clazz) { Comment }
      specify do
        expect(subject.dependencies.length).to eq(3)
      end
    end
  end

  context "#to_s" do
    context 'include polymorphic dependencies' do
      let(:clazz) { Comment }
      specify do
        expect(subject.to_s).to eq(<<~STR.chomp)
          digraph Comment {
            Comment [label="Comment"]
            Role [label="Role"]
            Comment -> Role [label="Comment#role_id"]
            User [label="User"]
            Role -> User [label="Role#user_id"]
            Product [label="Product"]
            Comment -> Product [label="Product#commentable_id"]
            Category [label="Category"]
            Product -> Category [label="Product#category_id"]
            OrderItem [label="OrderItem"]
            Comment -> OrderItem [label="OrderItem#commentable_id"]
            Order [label="Order"]
            OrderItem -> Order [label="OrderItem#order_id"]
            Order -> User [label="Order#user_id"]
            User -> Role [label="User#current_role_id"]
            OrderItem -> Product [label="OrderItem#product_id"]
          }
        STR
      end
    end
  end

  context "#fetch" do
    let(:clazz) { User }
    let(:except_keys) {  %w(User#current_role_id) }
    let(:fetch) { subject.fetch(additional_scope, except_keys) }

    context 'return all with no additional rules' do
      let(:additional_scope) { {} }
      specify do
        expect(fetch).to eq(User.all)
      end
    end

    context 'return additional rules when exists' do
      let(:clazz) { User }
      let(:additional_scope) { { 'User' => -> { where(id: 1) } } }
      specify do
        expect(fetch).to eq(User.where(id: 1))
      end
    end

    describe 'deep scopes' do
      context 'include additional scopes'do
        let(:clazz) { Order }
        let(:additional_scope) { { 'User' => -> { where(id: 1) } } }
        specify do
          expect(fetch).to eq(Order.where(user: User.where(id: 1)))
        end
      end

      context 'include additional scopes'do
        let(:clazz) { OrderItem }
        let(:additional_scope) do
          {
            'User' => -> { where(id: 1) },
            'Category' => -> { where(id: [1,2,3]) }
          }
        end

        specify do
          expect(fetch).to eq(
            OrderItem.where(
              order: Order.where(user: User.where(id: 1)),
              product: Product.where(
                category: Category.where(id: [1,2,3])
              )
            )
          )
        end
      end

      context 'include polymorphic dependencies' do
        let(:clazz) { Comment }
        let(:additional_scope) do
          {
            'Category' => -> { where(id: [1,2,3]) }
          }
        end

        specify do
          expect(fetch).to eq(
            Comment.where(
              commentable: Product.where(
                category: Category.where(id: [1,2,3])
              )
            ).union(Comment.where(
              commentable: OrderItem.where(
                product: Product.where(
                  category: Category.where(id: [1,2,3]))
               )
             )
           )
          )
        end
      end

      context 'inject additional scope in each polymorphic dependencies' do
        let(:clazz) { Comment }
        let(:additional_scope) do
          {
            'Comment' => -> { where(id: [1,2,3]) }
          }
        end

        specify do
          expect(fetch)
            .to eq(Comment.where( id: [1,2,3], commentable: Product.all)
              .union(Comment.where( id: [1,2,3], commentable: OrderItem.all)))
        end
      end
    end
  end
end

