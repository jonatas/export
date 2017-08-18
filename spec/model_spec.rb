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
        ))
    end
  end

  context 'single table inheritance dependencies' do
    context 'ignore inverse dependencies' do
      let(:clazz) { User }
      specify do
        expect(subject.polymorphic_dependencies).to be_empty
        expect(subject.dependencies).to have_key "current_role"
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

  describe '#graph_dependencies' do
    let(:clazz) { Comment }
    let(:output) { subject.graph_dependencies }

    context 'with dump show % of records being exported' do
      specify do
        out = output.gsub!(/"[\d\.]+%/m, '"x%') # replace % per x
        expect(out).to eq(<<~STR.chomp)
          digraph Comment {
            Comment [label="x% Comment"]
            Role [label="x% Role"]
            Comment -> Role
            User [label="x% User"]
            Role -> User
            Product [label="x% Product"]
            Comment -> Product [label="commentable"]
            Category [label="x% Category"]
            Product -> Category
            OrderItem [label="x% OrderItem"]
            Comment -> OrderItem [label="commentable"]
            Order [label="x% Order"]
            OrderItem -> Order
            User [label="x% User"]
            Order -> User
          }
        STR
      end
    end

    context 'without dump only entities' do
      subject { described_class.new clazz, nil }
      specify do
        expect(output).to eq(<<~STR.chomp)
          digraph Comment {
            Comment [label="Comment"]
            Role [label="Role"]
            Comment -> Role
            User [label="User"]
            Role -> User
            Product [label="Product"]
            Comment -> Product [label="commentable"]
            Category [label="Category"]
            Product -> Category
            OrderItem [label="OrderItem"]
            Comment -> OrderItem [label="commentable"]
            Order [label="Order"]
            OrderItem -> Order
            User [label="User"]
            Order -> User
          }
        STR
      end
    end
  end
end

