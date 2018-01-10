module Export
  # Represents the query of an exported model
  class Statement
    # The `Arel::SelectManager` responsible for the statement, where the
    # query can be defined.
    #
    # @return [Arel::SelectManager] the manager of the statement.
    attr_reader :manager

    # The binds of the statement. This tipically comes from a relation, but
    # can be easily adapted to someone's needs. When used inside of #to_sql,
    # every item inside the array must respond to `value_for_database`.
    #
    # @return [Array] the binds of the statement.
    attr_reader :binds

    # Creates a statement from an `ActiveRecord` relation.
    # The statement is created based on relation's `arel` and
    # `bound_attributes`.
    #
    # @param relation [Relation] the relation to be used.
    # @return [Statement] the new statement.
    def self.from_relation(relation)
      self.new(relation.arel, relation.bound_attributes)
    end

    # Creates a statement from a active record relation.
    # The statement is created based on relation's `arel` and
    # `bound_attributes`.
    #
    # @param manager [Arel::SelectManager] the manager.
    # @param binds [Array] the binds.
    # @return [Statement] the new statement.
    # @raise [Argument] if manager is `nil`.
    def initialize(manager, binds = [])
      raise ArgumentError unless manager

      @manager = manager
      @binds = binds
    end

    # Creates a new statement based on an existent statement.
    # This should be not called directly. Use #dup or #clone.
    #
    # @param other [Statement] the other statement.
    def initialize_copy(other)
      @manager = other.manager.dup
      @binds = other.binds.dup
    end

    # Returns a SQL query (from #manager) with bind params (?) replaced with
    # bind values (from #binds). Can end up with an invalid query if the number
    # of ? is higher than the number of binds.
    #
    # @return [String] the SQL query.
    def to_sql
      connection = ActiveRecord::Base.connection
      connection.unprepared_statement do
        connection.to_sql(@manager, @binds)
      end
    end

    # :nocov:
    def pretty_print(q)
      q.text(self.to_sql)
    end
    # :nocov:
  end
end
