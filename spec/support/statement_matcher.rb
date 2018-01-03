RSpec::Matchers.define :eq_statement do |expected|
  match do |actual|
    return ArgumentError, "expected that #{actual} would be a #{Export::Statement}" unless actual.is_a?(Export::Statement)

    if expected.is_a?(ActiveRecord::Relation)
      raise ArgumentError, 'cannot specify binds when expecting relation' if binds

      expected = Export::Statement.from_relation(expected)
    elsif expected.is_a?(Arel::SelectManager)
      expected = Export::Statement.new(expected, binds)
    end

    actual.query.to_sql == expected.query.to_sql && compare_binds(actual.binds, expected.binds)
  end

  chain :and_bind, :binds
  diffable

  failure_message do |actual|
    if actual.query != expected.query
      "expected that #{actual.query.to_sql.truncate(50)} would be #{expected.query.to_sql.truncate(50)}"
    else
      "expected that #{actual.binds} would be #{expected.binds}"
    end
  end

  def compare_binds(actual, expected)
    return false if !actual.is_a?(Array) || !expected.is_a?(Array)
    return false if actual.count != expected.count

    actual.each_with_index do |actual_bind, index|
      expected_bind = expected[index]

      actual_bind = actual_bind.value_for_database if actual_bind.respond_to?(:value_for_database)
      expected_bind = expected_bind.value_for_database if actual_bind.respond_to?(:value_for_database)

      return false unless actual_bind == expected_bind
    end

    true
  end
end

RSpec::Matchers.alias_matcher :query, :eq_statement
