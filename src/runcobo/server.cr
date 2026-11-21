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
    getter handlers : Array(HTTP::Handler)
    # SSL Certificate file.
    property cert : String? = nil
    # SSL key file.
    property key : String? = nil
    # Server instance.
    getter instance : HTTP::Server
    property shutdown_timeout : Time::Span = 30.seconds
    @requests = RequestTracker.new

    def initialize(@handlers : Array(HTTP::Handler) = Server.default_handlers)
      @instance = HTTP::Server.new([@requests] + handlers)
    end

    # Configure handlers before binding sockets or starting the server.
    def handlers=(handlers : Array(HTTP::Handler)) : Array(HTTP::Handler)
      unless instance.addresses.empty?
        raise ArgumentError.new("Cannot change handlers after binding the server")
      end
      @handlers = handlers
      @instance = HTTP::Server.new([@requests] + handlers)
      handlers
    end

    # Creates a TCPServer listening on `host`:`port`.
    def listen
      unless cert.nil? == key.nil?
        raise ArgumentError.new("Certificate and private key must be configured together")
      end
      raise ArgumentError.new("shutdown_timeout must be positive") unless shutdown_timeout > Time::Span.zero
      if (certificate_chain = cert) && (private_key = key)
        instance.bind_tls(host: host, port: port, context: generate_tls_context(certificate_chain, private_key), reuse_port: reuse_port)
      else
        instance.bind_tcp(host: host, port: port, reuse_port: reuse_port)
      end
      Runcobo::Log.info { "Runcobo #{Runcobo::VERSION} is listening on #{host}:#{port}" }
      Signal::INT.trap { close }
      Signal::TERM.trap { close }
      begin
        instance.listen
      ensure
        close
        begin
          @requests.drain(shutdown_timeout)
        ensure
          Signal::INT.reset
          Signal::TERM.reset
        end
      end
    end

    # Closes server.
    def close : Nil
      return if instance.closed?
      @requests.stop
      instance.close
      Runcobo::Log.info { "Goodbye!" }
    end

    # Creates a client for server.
    def client : HTTP::Client
      HTTP::Client.new(host, port)
    end

    # Default handlers can be replaced before the server binds its sockets.
    def self.default_handlers : Array(HTTP::Handler)
      handlers = [] of HTTP::Handler
      handlers << Runcobo::LogHandler.new unless ENV["SKIP_LOG"]? == "true"
      handlers << Runcobo::RouteHandler.new
      handlers << Runcobo::RouteNotFoundHandler.new
      handlers
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
