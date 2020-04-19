require "http/server/handler"

module Runcobo
  class RouteNotFoundHandler
    include HTTP::Handler

    def call(context)
      context.response.status_code = 404
      context.response.print "404"
      context
    end
  end
end
