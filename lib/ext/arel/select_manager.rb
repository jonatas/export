Arel::SelectManager.class_eval do
  def prepend_with *subqueries
    subqueries = subqueries + self.ast.with.children if self.ast.with

    with(subqueries)
  end
end
