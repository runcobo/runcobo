require "radix"
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
    # Radix Tree for classes inheriated from `BaseAction`
    TREE = ::Radix::Tree(self.class).new
    # Route table
    ROUTES = [] of Runcobo::Route
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

    def params
      {__action: self.class.name}.merge(query_params).merge(form_params).merge(json_params).merge(url_params)
    end

    def query_params
      NamedTuple.new
    end

    def url_params
      NamedTuple.new
    end

    def form_params
      NamedTuple.new
    end

    def json_params
      NamedTuple.new
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
