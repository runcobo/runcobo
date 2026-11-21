require "http/server"

class HTTP::Server::Response
  # Observers can distinguish failures before a response from interrupted streams.
  def headers_sent? : Bool
    wrote_headers?
  end
end
