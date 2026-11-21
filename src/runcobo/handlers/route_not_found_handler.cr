require "http/server/handler"

module Runcobo
  class RouteNotFoundHandler
    include HTTP::Handler

    def initialize
      @handler = nil
    end

    def initialize(&@handler : HTTP::Server::Context ->)
    end

    def call(context)
      if handler = @handler
        handler.call(context)
        return context
      end
      context.response.status_code = 404
      context.response.print "404"
      context
    end
  end
end
