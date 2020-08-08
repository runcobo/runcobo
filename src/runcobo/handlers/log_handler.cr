require "http/server/handler"
require "uuid"

module Runcobo
  class LogHandler
    include HTTP::Handler

    def call(context)
      start = Time.monotonic
      context.request.request_id = UUID.random
      Runcobo::Log.info { "[#{context.request.request_id}] #{context.request.method} #{context.request.resource}" }
      call_next(context)
      duration = Time.monotonic - start
      Runcobo::Log.info { "[#{context.request.request_id}] Completed #{context.response.status_code} in #{elapsed_text(duration)}\n" }
    end

    def elapsed_text(elapsed : Time::Span) : String
      minutes = elapsed.total_minutes
      return "#{minutes.round(2)}m" if minutes >= 1

      seconds = elapsed.total_seconds
      return "#{seconds.round(2)}s" if seconds >= 1

      millis = elapsed.total_milliseconds
      return "#{millis.round(2)}ms" if millis >= 1

      "#{(millis * 1000).round(2)}µs"
    end
  end
end
