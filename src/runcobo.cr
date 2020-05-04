require "jbuilder"
require "./tops/**"
require "./runcobo/**"
require "./commands/**"
require "radix"

module Runcobo
  # Starts Runcobo App with default host "0.0.0.0" and default port "3000".
  #
  # Or read ENV["HOST"] as host, read ENV["PORT"] as port.
  # ```
  # Runcobo.start
  # ```
  #
  # Starts with custom host and custom port.
  # ```
  # Runcobo.start(host: "0.0.0.0", port: "5000")
  # ```
  def self.start(*, host : String? = ENV["HOST"]? || "0.0.0.0", port : Int32 = (ENV["PORT"]? || 3000).to_i)
    server = Runcobo::Server.new
    server.host = host
    server.port = port
    server.listen
  end
end
