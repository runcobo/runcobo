require "jbuilder"
require "water"
require "./tops/**"
require "./runcobo/**"
require "./commands/**"
require "radix"

module Runcobo
  # Starts Runcobo App with host ("0.0.0.0"), port (3000), reuse_port (false) and handlers (Runcobo::Server.default_handlers).
  #
  # Or read ENV["HOST"] as host, read ENV["PORT"] as port.
  # ```
  # Runcobo.start
  # ```
  #
  # Starts with custom host, port, reuse_port, handlers, cert and key.
  # ```
  # Runcobo.start(
  #   host: "0.0.0.0",
  #   port: "5000",
  #   reuse_port: true,
  #   handlers: [
  #     Runcobo::RouteHandler.new,
  #     Runcobo::RouteNotFoundHandler.new,
  #   ],
  #   cert: "localhost.crt",
  #   key: "localhost.key"
  # )
  # ```
  def self.start(*,
                 host : String = ENV["HOST"]? || "0.0.0.0",
                 port : Int32 = (ENV["PORT"]? || 3000).to_i,
                 reuse_port : Bool = !!(ENV["REUSE_PORT"]? || false),
                 handlers : Array(HTTP::Handler) = Runcobo::Server.default_handlers,
                 cert : String? = ENV["CERT"]?,
                 key : String? = ENV["KEY"]?)
    server = Runcobo::Server.new
    server.host = host
    server.port = port
    server.reuse_port = reuse_port
    server.handlers = handlers
    server.cert = cert
    server.key = key
    server.listen
  end

  # Pretty prints envs which can be used in Runcobo.
  def self.pretty_print_envs
    pp({
      HOST:       "(String) The host app listen on",
      PORT:       "(Int32)  The port app listen on",
      REUSE_PORT: "(Bool)   Whether reuse port",
      CERT:       "(String) Cert for https",
      KEY:        "(String) Key for https",
    })
  end
end
