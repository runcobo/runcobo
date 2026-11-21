require "request_validation"
require "./request_input"

module Runcobo
  module Validation
    struct Issue
      include JSON::Serializable

      getter source : String
      getter path : Array(RequestValidation::PathSegment)
      getter code : Symbol
      getter params : Hash(String, RequestValidation::ErrorParam)

      def initialize(@source : String, error : RequestValidation::Error)
        @path = error.path.dup
        @code = error.code
        @params = error.params.dup
      end
    end

    class Failure < Exception
      getter issues : Array(Issue)
      getter status_code : Int32

      def initialize(@issues : Array(Issue), @status_code : Int32 = 422)
        super("Request validation failed")
      end
    end

    class RequestError < Failure
      getter issue : Issue

      def initialize(source : String, code : Symbol, status_code : Int32)
        @issue = Issue.new(source, RequestValidation::Error.new([] of RequestValidation::PathSegment, code))
        super([@issue], status_code)
      end
    end

    macro contract_params(source, type, *, unknown_keys = :strip)
      {% if type.is_a?(Generic) && ["NamedTuple", "::NamedTuple"].includes?(type.name.stringify) %}
        {% raise "NamedTuple parameter declarations were removed in Runcobo 3.0; declare a RequestValidation::Contract instead" %}
      {% end %}
      {% unless type.is_a?(Path) && type.resolve < RequestValidation::Contract %}
        {% raise "Expected a RequestValidation::Contract type" %}
      {% end %}
      {% unless [:reject, :strip].includes?(unknown_keys) %}
        {% raise "unknown_keys must be :reject or :strip" %}
      {% end %}

      @[Runcobo::Parameter(source: {{source}})]
      private def {{"__runcobo_#{source.id}_declaration_#{type.line_number}_#{type.column_number}".id}}
      end

      @{{source.id}}_input : {{type}}::Output?

      protected def build_{{source.id}}_contract
        {{type}}.new(unknown_keys: {{unknown_keys}})
      end

      def {{source.id}}_input : {{type}}::Output
        @{{source.id}}_input ||= validate(build_{{source.id}}_contract, source: {{source}})
      end

      {% verbatim do %}
        macro finished
          {% declarations = [] of Def %}
          {% for owner in [@type] + @type.ancestors %}
            {% for method in owner.methods %}
              {% if method.annotation(Runcobo::Parameter) %}
                {% declarations << method %}
              {% end %}
            {% end %}
          {% end %}
          {% sources = declarations.map { |method| method.annotation(Runcobo::Parameter)[:source] } %}
          {% if sources.uniq.size != sources.size %}
            {% raise "A request source can only have one contract (including inherited declarations)" %}
          {% end %}
          {% if sources.includes?(:json) && sources.includes?(:form) %}
            {% raise "An action cannot declare both json and form contracts" %}
          {% end %}

          {% if sources.size == 1 %}
            def input
              {{sources.first.id}}_input
            end
          {% else %}
            macro input
              \{% raise "Multiple request contracts: use url_input, query_input, form_input or json_input" %}
            end
          {% end %}

          protected def validate_declared_inputs : Nil
            issues = [] of Runcobo::Validation::Issue
            status_code = 422
            {% for source in sources %}
              begin
                {{source.id}}_input
              rescue failure : Runcobo::Validation::Failure
                issues.concat(failure.issues)
                status_code = failure.status_code if status_code == 422
              end
            {% end %}
            raise Runcobo::Validation::Failure.new(issues, status_code) unless issues.empty?
          end
        end
      {% end %}
    end

    # Opt in with before_request read_input to check bodies even without a contract.
    protected def read_input
      request.runcobo_input.merged(max_request_body_size)
      continue
    end

    protected def upload(name : String) : UploadFile
      request.runcobo_input.upload(name, max_request_body_size)
    end

    protected def uploads(name : String) : Array(UploadFile)
      request.runcobo_input.uploads(name, max_request_body_size)
    end

    # All contract entries share source reading, native conversion and failure handling.
    protected def validate(type : T.class, *, strict = false) forall T
      validate(T.new(unknown_keys: strict ? RequestValidation::UnknownKeys::Reject : RequestValidation::UnknownKeys::Strip))
    end

    protected def validate(contract : T, *, source : Symbol = :request) forall T
      data = contract_input(source)
      result = case data
               when RequestValidation::SourcedInput then contract.from_sources(data)
               when JSON::Any                       then contract.from_json(data)
               else                                      contract.from_params(data)
               end
      unless result.errors.empty?
        raise Failure.new(result.errors.map { |error| Issue.new(source.to_s, error) })
      end
      result.value!
    end

    protected def validate_declared_inputs : Nil
    end

    private def contract_input(source : Symbol)
      case source
      when :request then request.runcobo_input.contract_input(max_request_body_size)
      when :json    then request.runcobo_input.json(max_request_body_size)
      when :form    then request.runcobo_input.form(max_request_body_size)
      when :query   then request.runcobo_input.query
      when :url     then request.route_params
      else               raise ArgumentError.new("Unknown contract source: #{source}")
      end
    rescue failure : RequestError
      raise failure if source == :request
      raise RequestError.new(source.to_s, failure.issue.code, failure.status_code)
    end

    # Override per action when a larger or smaller request body is required.
    def max_request_body_size : Int64
      request.runcobo_input.max_body_size
    end

    protected def render_validation_errors(issues : Array(Validation::Issue), *, status_code : Int32) : HTTP::Server::Context
      render_json({errors: issues}, status_code: status_code)
    end
  end
end
