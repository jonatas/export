module Export
  # Represents the query of an exported model
  class Statement
    Bind = Struct.new(:value_for_database)

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
      self.new(relation.model, relation.arel, relation.bound_attributes)
    end

    # Creates a statement from a active record relation.
    # The statement is created based on relation's `arel` and
    # `bound_attributes`.
    #
    # @param clazz [Class] the active record.
    # @param manager [Arel::SelectManager] the manager.
    # @param binds [Array] the binds.
    # @return [Statement] the new statement.
    # @raise [Argument] if manager is `nil`.
    def initialize(clazz, manager, binds = [])
      raise ArgumentError unless clazz
      raise ArgumentError unless manager

      @clazz = clazz
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
      connection.unprepared_statement do
        connection.to_sql(@manager, @binds)
      end
    end

    # Executes the whole query and returns the results as an array of
    # `Result`, from Active Record. Each result has a `value` hash. If
    # a block is given, each result is gonna be yielded to the block.
    #
    # @return [Enumerable] the enumerable with the results, if no block
    #                      is given.
    def execute
      return to_enum(:execute) unless block_given?

      connection.select_all(@manager, nil, @binds).each { |r| yield r }
    end

    # Executes the query in batches of `size` and yields each of the
    # results (`Result`, from Active Record) to the block given.
    #
    # @param size [Integer] the size of each query in the database.
    def execute_in_batches(size: 1000)
      raise ArgumentError, 'batches need a block to yield to' unless block_given?

      id = 0
      id_column = @manager.source.left[@clazz.primary_key]

      manager = Arel::SelectManager.new(@manager.as(@clazz.table_name))
      manager.project(Arel.star)
             .where(id_column.gt(Arel::Nodes::BindParam.new))
             .order(id_column)
             .take(size)

      statement = self.class.new(@clazz, manager, @binds + [nil])

      loop do
        statement.binds[statement.binds.count - 1] = Bind.new(id)
        results = statement.execute.to_a
        results.each { |r| yield r }

        break if results.count < size

        id = results.last[@clazz.primary_key]
      end
    end

    # :nocov:
    def pretty_print(q)
      q.text(self.to_sql)
    end
    # :nocov:

    private

    private_constant :Bind

    def connection
      ActiveRecord::Base.connection
    end
  end
end
