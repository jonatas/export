module Export
  # Represents the query of an exported model
  class Statement
    attr_reader :query
    attr_reader :binds

    def self.from_relation(relation)
      self.new(relation.arel, relation.bound_attributes)
    end

    def initialize(query, binds = [])
      raise ArgumentError unless query

      @query = query
      @binds = binds
    end

    def initialize_copy other
      @query = other.query.dup
      @binds = other.binds.dup
    end

    def to_sql
      connection = ActiveRecord::Base.connection
      connection.unprepared_statement do
        connection.to_sql(@query, @binds)
      end
    end

    def pretty_print(q)
      q.text(self.to_sql)
    end
  end
end
