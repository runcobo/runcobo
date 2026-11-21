require "http/server/handler"
require "uuid"
require "../response"

module Runcobo
  class LogHandler
    include HTTP::Handler

    def call(context)
      incoming = context.request.headers["X-Request-Id"]?
      request_id = incoming && !incoming.strip.empty? ? incoming : UUID.random.to_s
      context.request.request_id = request_id
      context.response.headers["X-Request-Id"] = request_id
      started = Time.instant
      ::Log.with_context(request_id: request_id) do
        failed = false
        begin
          call_next(context)
        rescue error
          failed = true
          response = context.response
          status = response.headers_sent? || error.is_a?(HTTP::Server::ClientError) ? response.status_code : 500
          Runcobo::Log.error(exception: error) { "request_failed request_id=#{request_id} method=#{context.request.method} path=#{context.request.path} status=#{status} elapsed_ms=#{(Time.instant - started).total_milliseconds.round(3)}" }
          raise error
        ensure
          unless failed
            Runcobo::Log.info { "request_completed request_id=#{request_id} method=#{context.request.method} path=#{context.request.path} status=#{context.response.status_code} elapsed_ms=#{(Time.instant - started).total_milliseconds.round(3)}" }
          end
        end
      end
    end
  end
end
