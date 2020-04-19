module Runcobo
  # Defines form params.
  #
  # ```
  # class FormParamsExample < BaseAction
  #   get "/params"
  #   form NamedTuple(id: Int64, category: String)
  #
  #   call do
  #     sum = form[:id] + 6
  #     render_plain "#{sum}: #{category}"
  #   end
  # end
  # ```
  module Params::Form
    macro form(code)
      def form
        params = HTTP::Params.parse(@raw_body || "")
        NamedTuple.new(
          {% for key, value in code.named_args %}
            {% if value.stringify.starts_with?("Array") %}
              {{key.id}}: {{value}}.from_http_param(params.fetch_all({{key.stringify}})),
            {% elsif value.stringify.includes?("Nil") %}
              {{key.id}}: {{value.types[0]}}.from_http_param(params[{{key.stringify}}]?),
            {% else %}
              {{key.id}}: {{value}}.from_http_param(params[{{key.stringify}}]),
            {% end %}
          {% end %}
        )
      end
    end
  end
end
