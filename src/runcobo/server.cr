require "http/server"

module Runcobo
  class Server
    # Host, defaults to ENV["HOST"] or "0.0.0.0".
    property host : String = ENV["HOST"]? || "0.0.0.0"
    # Port, defaults to ENV["PORT"] or 3000.
    property port : Int32 = (ENV["PORT"]? || 3000).to_i
    # Reuse Port, defaults to false.
    property reuse_port : Bool = false
    # Handlers, defaults to `.default_handlers`.
    property handlers : Array(HTTP::Handler) = default_handlers
    # Server instance.
    getter instance : HTTP::Server

    def initialize
      @instance = HTTP::Server.new(handlers)
    end

    # Creates a TCPServer listening on `host`:`port`.
    def listen
      Runcobo::Log.info { "listen on #{host}:#{port}" }
      instance.bind_tcp(host: host, port: port, reuse_port: reuse_port)
      Signal::INT.trap { close }
      Signal::TERM.trap { close }
      instance.listen
    end

    # Closes server.
    def close : Nil
      Runcobo::Log.info { "=== shutdown: #{Time.local} ===" }
      Runcobo::Log.info { "Goodbye!" }
      instance.close
      Signal::INT.reset
    end

    # Creates a client for server.
    def client : HTTP::Client
      HTTP::Client.new(host, port)
    end

    # Set Default handlers, you can change them by `handlers=` after `initialize`.
    def self.default_handlers : Array(HTTP::Handler)
      [
        Runcobo::RouteHandler.new,
        Runcobo::RouteNotFoundHandler.new,
      ] of HTTP::Handler
    end
  end
end
