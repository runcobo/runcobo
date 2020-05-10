module Runcobo
  # Defines url params.
  #
  # ```
  # class UrlParamsExample < BaseAction
  #   get "/params/:id/:category"
  #   url NamedTuple(id: Int64, category: String)
  #
  #   call do
  #     sum = params[:id] + 6
  #     render_plain "#{sum}: #{category}"
  #   end
  # end
  # ```
  module Params::Url
    macro url(code)
      def url_params
        _params = request.route_params
        NamedTuple.new(
          {% for key, value in code.named_args %}
            {% if value.stringify.includes?("Nil") %}
              {{key.stringify}}: {{value.types[0]}}.from_http_param(_params[{{key.stringify}}]?),
            {% else %}
              {{key.stringify}}: {{value}}.from_http_param(_params[{{key.stringify}}]),
            {% end %}
          {% end %}
        )
      end
    end
  end
end
