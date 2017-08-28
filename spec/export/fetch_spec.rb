require 'spec_helper'

describe Export::Fetch do

  include_examples 'database setup'

  subject { described_class.new(dependency_tree, additional_scope) }

  let(:additional_scope) { {} }
  let(:except_keys) {  %w(User#current_role_id) }
  let(:dependency_tree) { Export::DependencyTree.new clazz, except_keys: except_keys }
  let(:clazz) { User }

  context "#scope" do
    let(:fetch) { subject.scope }

    context 'return all with no additional rules' do
      specify do
        expect(fetch).to eq(User.all)
      end
    end

    context 'return additional rules when exists' do
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

      context 'with polymorphic dependencies' do
        let(:clazz) { Comment }
        let(:additional_scope) do
          {
            'Category' => -> { where(id: [1,2,3]) }
          }
        end

        specify 'include union repeating the scope for each dependency' do
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

      context 'inject additional scope' do
        let(:clazz) { Comment }
        let(:additional_scope) do
          {
            'Comment' => -> { where(id: [1,2,3]) }
          }
        end

        specify 'ignore union all if no polymorphic dependencies uses additional scopes' do
          expect(fetch).to eq(Comment.where( id: [1,2,3]))
        end
      end
    end
  end
end

