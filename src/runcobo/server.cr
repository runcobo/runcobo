require "http/server"

module Runcobo
  class Server
    # Host, defaults to ENV["HOST"] or "0.0.0.0".
    property host : String = ENV["HOST"]? || "0.0.0.0"
    # Port, defaults to ENV["PORT"] or 3000.
    property port : Int32 = (ENV["PORT"]? || 3000).to_i
    # Handlers, defaults to `.default_handlers`.
    property handlers : Array(HTTP::Handler) = default_handlers
    # Logger, default to STDOUT`
    property logger : Runcobo::Logger = Runcobo::Logger.new(STDOUT)
    # Server instance.
    getter instance : HTTP::Server

    def initialize
      @instance = HTTP::Server.new(@handlers)
    end

    # Creates a TCPServer listening on `host`:`port`.
    def listen
      logger.start("listen on #{host}:#{port}")
      instance.bind_tcp(host: host, port: port)
      Signal::INT.trap { close }
      Signal::TERM.trap { close }
      instance.listen
    end

    # Closes server.
    def close : Nil
      logger.info("=== shutdown: #{Time.local} ===")
      logger.info("Goodbye!")
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
