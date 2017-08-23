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
      expect(subject.dependencies.keys).to eq(%w(Role#user_id))
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
        expect(name).to eq("Role#current_role_id")
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
        puts subject
      end
    end
  end
end

