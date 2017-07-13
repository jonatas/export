require 'spec_helper'

describe Export::Model do

  include_examples 'database setup'

  subject { described_class.new clazz, dump }

  let(:dump) do
    Export::Dump.new 'one user' do
      model(User) { order(:id).limit(1) }
    end
  end

  context "#scope" do
    context 'simple user with a limit' do
      let(:clazz) { User }

      specify do
        expect(subject.scope).to eq(User.order(:id).limit(1))
      end
    end

    context 'order depends exported users' do
      let(:clazz) { Order }

      specify do
        expect(subject.scope).to eq(Order.where(user: User.order(:id).limit(1)))
      end
    end

    context 'product depends categories' do
      let(:clazz) { Product }

      specify do
        expect(subject.scope).to eq( Product.all )
      end
    end

    context 'order item depends order and products' do
      let(:clazz) { OrderItem }

      specify do
        expect(subject.scope).to eq(
          OrderItem.where(
            order: Order.where(
              user: User.order(:id).limit(1)
            )
          )
        )
      end
    end
  end

  context 'Ignore nullable foreign keys from relationship' do
    let(:clazz) { Role }
    specify do
      expect(subject.scope).to eq(
        Role.where(user: User.order(:id).limit(1)))
    end
  end

  context 'polymorphic dependencies' do
    let(:clazz) { Comment }

    specify do
      expect(subject.scope).to eq(
        Comment.where(
          role: Role.where(user: User.order(:id).limit(1) ),
          commentable: Product.all
        ).union(
          Comment.where(
            role: Role.where(user: User.order(:id).limit(1)),
            commentable: OrderItem.where(
              order: Order.where(
                user: User.order(:id).limit(1))))
        )
      )
    end
  end

  context 'single table inheritance dependencies' do
    context 'ignore inverse dependencies' do
      let(:clazz) { User }
      specify do
        expect(subject.dependencies).to be_empty
        expect(subject.polymorphic_dependencies).to be_empty
      end
    end
    context 'inverse dependencies' do
      let(:clazz) { Role }
      specify do
        expect(subject.dependencies).not_to be_empty
        expect(subject.polymorphic_dependencies).to be_empty
      end
    end
  end
end

