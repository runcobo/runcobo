require "http/server/handler"

module Runcobo
  class RouteHandler
    include HTTP::Handler

    def call(context)
      url = "/#{context.request.method}#{context.request.path}"
      result = Runcobo::Action::TREE.find(url)
      if result.found?
        context.request.route_params = result.params
        Runcobo::Log.info { "#{context.request.method} #{context.request.resource}" }
        result.payload.new(context).call
      else
        call_next(context)
      end
    end
  end
end
