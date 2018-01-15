RSpec::Matchers.define :eq_statement do |expected|
  match do |actual|
    begin
      raise ArgumentError, "expected that #{actual} would be a #{Export::Statement}" unless actual.is_a?(Export::Statement)

      if expected.is_a?(ActiveRecord::Relation)
        raise ArgumentError, 'cannot specify binds when expecting relation' if binds

        expected = expected.select(expected.model.column_names) if expected.select_values.empty?
        expected = Export::Statement.from_relation(expected)
      elsif expected.is_a?(Arel::SelectManager)
        clazz = ActiveRecord::Base.descendants.find { |c| c.table_name == expected.source.left.name }
        expected = Export::Statement.new(clazz, expected, database_binds)
      end

      actual_sql = actual.to_sql
      expected_sql = expected.to_sql

      raise 'expected that actual query would not have pending binds' if actual_sql.include?('?')
      raise 'expected that expected query would not have pending binds' if expected_sql.include?('?')

      if actual_sql != expected_sql
        raise 'expected that query would match' unless actual.manager.to_sql == expected.manager.to_sql
        raise 'expected that binds would match'
      end

      ActiveRecord::Base.connection.raw_connection.prepare(actual_sql).close

      true
    rescue => e
      @failure_message = e.message

      false
    end
  end

  chain :and_bind, :binds
  diffable

  description do
    "scope with #{expected.to_sql.truncate(100)}"
  end

  failure_message do
    @failure_message
  end

  def database_binds
    binds.map do |bind|
      bind.respond_to?(:value_for_database) ? bind : DatabaseBind.new(bind)
    end
  end
end

RSpec::Matchers.alias_matcher :query, :eq_statement

DatabaseBind = Struct.new(:value_for_database)
