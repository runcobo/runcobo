require "../request_info"
require "../extensions/request"
require "../response"

module Runcobo
  class RequestInfoHandler
    include HTTP::Handler

    def initialize(@proxy_config : ProxyConfig = ProxyConfig.new)
    end

    def call(context)
      context.request.runcobo_request_info = RequestInfo.new(
        context.request,
        peer: context.remote_address.as?(Socket::IPAddress),
        local: context.local_address.as?(Socket::IPAddress),
        secure: context.response.runcobo_secure_transport?,
        proxy_config: @proxy_config,
      )
      call_next(context)
    end
  end
end
