module CrSQLExample
  abstract class BaseAction < ::BaseAction
    @store : Store::Queries?

    def store=(store : Store::Queries)
      @store = store
    end

    protected def store : Store::Queries
      @store || raise "Store was not provided by StoreRouteHandler"
    end
  end
end
