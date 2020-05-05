require "http/server"
require "openssl"

module Runcobo
  class Server
    # Host, defaults to "0.0.0.0".
    property host : String = "0.0.0.0"
    # Port, defaults to 3000.
    property port : Int32 = 3000
    # Reuse Port, defaults to false.
    property reuse_port : Bool = false
    # Handlers, defaults to `.default_handlers`.
    property handlers : Array(HTTP::Handler) = default_handlers
    # SSL Certificate file.
    property cert : String? = nil
    # SSL key file.
    property key : String? = nil
    # Server instance.
    getter instance : HTTP::Server

    def initialize
      @instance = HTTP::Server.new(handlers)
    end

    # Creates a TCPServer listening on `host`:`port`.
    def listen
      Runcobo::Log.info { "listen on #{host}:#{port}" }
      if (certificate_chain = cert) && (private_key = key)
        instance.bind_tls(host: host, port: port, context: generate_tls_context(certificate_chain, private_key), reuse_port: reuse_port)
      else
        instance.bind_tcp(host: host, port: port, reuse_port: reuse_port)
      end
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

    # Generate TLS context with certificate_chain and private_key
    def generate_tls_context(certificate_chain : String, private_key : String) : OpenSSL::SSL::Context::Server
      context = OpenSSL::SSL::Context::Server.new
      context.certificate_chain = certificate_chain
      context.private_key = private_key
      context
    end
  end
end
