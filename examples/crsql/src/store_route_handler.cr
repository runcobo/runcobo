module CrSQLExample
  class StoreRouteHandler < Runcobo::RouteHandler
    def initialize(@store : Store::Queries)
    end

    protected def build_action(action_class : Runcobo::Action.class, context : HTTP::Server::Context) : Runcobo::Action
      action = super
      action.store = @store if action.is_a?(CrSQLExample::BaseAction)
      action
    end
  end

  def self.handlers(store : Store::Queries) : Array(HTTP::Handler)
    handlers = [] of HTTP::Handler
    handlers << Runcobo::LogHandler.new unless ENV["SKIP_LOG"]?
    handlers << StoreRouteHandler.new(store)
    handlers << Runcobo::RouteNotFoundHandler.new
    handlers
  end
end
