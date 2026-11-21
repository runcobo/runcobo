require "radix"
require "./validation"
require "./actions/router"
require "./actions/redirector"
require "./actions/render"
require "./actions/pipe"
require "./actions/params/form"
require "./actions/params/json"
require "./actions/params/query"
require "./actions/params/url"

module Runcobo
  annotation Parameter
  end

  abstract class Action
    LAYOUT = ""
    # Radix Tree for classes inheriated from `BaseAction`
    TREE = ::Radix::Tree(self.class).new
    # Route table
    ROUTES = [] of Runcobo::Route
    extend Runcobo::Router
    include Runcobo::Redirector
    include Runcobo::Render
    include Runcobo::Pipe
    include Runcobo::Validation
    include Runcobo::Params::Form
    include Runcobo::Params::Json
    include Runcobo::Params::Query
    include Runcobo::Params::Url

    abstract def call

    property context : HTTP::Server::Context
    property request : HTTP::Request

    def raw_body : String?
      request.runcobo_input.raw_body
    end

    def initialize(@context : HTTP::Server::Context)
      @request = @context.request
    end

    def validation_response : HTTP::Server::Context?
      nil
    end

    macro call(&body)
      def call
        %early_result = run_before_request_actions
        return @context if %early_result.is_a?(Runcobo::Pipe::Byebye)
        if %validation_response = validation_response
          return %validation_response
        end
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
      rescue %validation_error : Runcobo::Validation::Failure
        render_validation_errors(%validation_error.issues, status_code: %validation_error.status_code)
      end
    end
  end
end
