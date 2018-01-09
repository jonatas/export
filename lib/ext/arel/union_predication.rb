module Arel
  module UnionPredication
    def union_all other
      left = self.respond_to?(:ast) ? self.ast : self
      right = other.respond_to?(:ast) ? other.ast : other

      Nodes::UnionAll.new left, right
    end
  end
end
