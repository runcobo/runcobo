require "./actions/router"
require "./actions/render"
require "./actions/pipe"
require "./actions/params/form"
require "./actions/params/json"
require "./actions/params/query"
require "./actions/params/url"

module Runcobo
  abstract class Action
    LAYOUT = nil : String?
    extend Runcobo::Router
    include Runcobo::Render
    include Runcobo::Pipe
    include Runcobo::Params::Form
    include Runcobo::Params::Json
    include Runcobo::Params::Query
    include Runcobo::Params::Url

    abstract def call

    property context : HTTP::Server::Context
    property request : HTTP::Request
    property raw_body : String?

    def initialize(@context : HTTP::Server::Context)
      @request = @context.request
      if @request.body
        @raw_body = @request.body.not_nil!.gets_to_end
      end
    end

    macro call(&body)
      def call
        %pipe_result = call_before_actions
        if %pipe_result.is_a?(Runcobo::Pipe::Byebye)
          %context = @context
        else
          %context = {{ yield }}
        end

        %pipe_result = call_after_actions
        if %pipe_result.is_a?(Runcobo::Pipe::Byebye)
          @context
        else
          %context
        end
      end
    end
  end
end