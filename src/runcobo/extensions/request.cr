require "uuid"
require "../request_info"

module HTTP
  class Request
    property request_id : String?
    # :nodoc:
    property runcobo_request_info : Runcobo::RequestInfo?

    private def request_info : Runcobo::RequestInfo
      runcobo_request_info || Runcobo::RequestInfo.new(self)
    end

    delegate scheme, protocol, host, port, base_url, remote_ip, ssl?, to: request_info
  end
end
