require "http/server"
require "openssl"

class HTTP::Server::Response
  # :nodoc:
  def runcobo_secure_transport? : Bool
    @io.is_a?(OpenSSL::SSL::Socket)
  end

  # Observers can distinguish failures before a response from interrupted streams.
  def headers_sent? : Bool
    wrote_headers?
  end
end
