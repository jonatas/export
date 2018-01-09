Arel::Visitors::ToSql.class_eval do
  def visit_Arel_Nodes_UnionAll o, collector
    infix_value(o, collector, " UNION ALL ")
  end
end
