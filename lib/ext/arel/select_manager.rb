Arel::SelectManager.class_eval do
  include Arel::UnionPredication

  def prepend_with *subqueries
    subqueries = subqueries + self.ast.with.children if self.ast.with

    with(subqueries)
  end

  # :nocov:
  def pretty_print(q)
    q.text(self.to_sql)
  end
  # :nocov:
end
