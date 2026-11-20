require "http/server/handler"

module Runcobo
  class RouteHandler
    include HTTP::Handler

    def call(context)
      url = "/#{context.request.method}#{context.request.path}"
      result = Runcobo::Action::TREE.find(url)
      if result.found?
        context.request.route_params = result.params
        build_action(result.payload, context).call
      else
        call_next(context)
      end
    end

    # Applications can attach typed dependencies before an action is called.
    protected def build_action(action_class : Runcobo::Action.class, context : HTTP::Server::Context) : Runcobo::Action
      action_class.new(context)
    end
  end
end
