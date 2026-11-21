require "http/server"

module Runcobo
  # Stop admission before closing listeners, then wait for admitted requests.
  class RequestTracker
    include HTTP::Handler
    @active = 0
    @stopping = false
    @waiting = false
    @mutex = Mutex.new
    @idle = Channel(Nil).new(1)

    def call(context)
      admitted = @mutex.synchronize do
        unless @stopping
          @active += 1
          true
        end
      end
      unless admitted
        context.response.status_code = 503
        context.response.headers["Connection"] = "close"
        return
      end
      begin
        call_next(context)
      ensure
        notify = @mutex.synchronize do
          @active -= 1
          @active == 0 && @waiting
        end
        @idle.send(nil) if notify
      end
    end

    def stop : Nil
      @mutex.synchronize { @stopping = true }
    end

    def drain(timeout : Time::Span) : Nil
      waiting = @mutex.synchronize do
        @waiting = @active > 0
      end
      return unless waiting
      select
      when @idle.receive
      when timeout(timeout)
        count = @mutex.synchronize { @active }
        Runcobo::Log.warn { "shutdown_timed_out active_requests=#{count}" }
      end
    end
  end
end
