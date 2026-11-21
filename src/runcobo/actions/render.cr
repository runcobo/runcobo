require "json"
require "../views"

module Runcobo
  module Render
    # Inherited by child actions; nil disables the default layout.
    macro layout(filename)
      LAYOUT = {{ filename }}
    end

    # Render the current action or a literal template name using the configured engine.
    macro render(*, layout = :inherit, status_code = 200, dir = nil, layout_dir = nil, engine = nil)
      render nil, layout: {{layout}}, status_code: {{status_code}}, dir: {{dir}}, layout_dir: {{layout_dir}}, engine: {{engine}}
    end

    macro render(template, *, layout = :inherit, status_code = 200, dir = nil, layout_dir = nil, engine = nil)
      ::Runcobo::Views.render {{template}}, action_type: {{@type}}, layout: {{layout}},
        dir: {{dir}}, layout_dir: {{layout_dir}}, engine: {{engine}}, context: @context, status_code: {{status_code}}
    end

    # Same conventions as render, without writing the response.
    macro render_to_string(*, layout = :inherit, dir = nil, layout_dir = nil, engine = nil)
      render_to_string nil, layout: {{layout}}, dir: {{dir}}, layout_dir: {{layout_dir}}, engine: {{engine}}
    end

    macro render_to_string(template, *, layout = :inherit, dir = nil, layout_dir = nil, engine = nil)
      ::Runcobo::Views.render {{template}}, action_type: {{@type}}, layout: {{layout}},
        dir: {{dir}}, layout_dir: {{layout_dir}}, engine: {{engine}}
    end

    # Explicit engine entries retain paths relative to the template root.
    macro render_jbuilder(filename, *, layout = :inherit, status_code = 200, dir = nil, layout_dir = nil)
      ::Runcobo::Views.render {{filename}}, action_type: {{@type}}, relative_to_action: false,
        layout: {{layout}}, dir: {{dir}}, layout_dir: {{layout_dir}}, engine: :jbuilder,
        context: @context, status_code: {{status_code}}
    end

    macro render_water(filename, *, layout = :inherit, status_code = 200, dir = nil, layout_dir = nil)
      ::Runcobo::Views.render {{filename}}, action_type: {{@type}}, relative_to_action: false,
        layout: {{layout}}, dir: {{dir}}, layout_dir: {{layout_dir}}, engine: :water,
        context: @context, status_code: {{status_code}}
    end

    # Renders a value directly without a template.
    def render_json(value, *, status_code : Int32 = 200) : HTTP::Server::Context
      @context.response.content_type = "application/json"
      @context.response.status_code = status_code
      value.to_json(@context.response.output)
      @context
    end

    # Explicitly send an empty response. The action chooses when to use this;
    # other renderers do not suppress output based on the request method or status.
    def render_empty(*, status_code : Int32 = 200, content_type : String? = nil) : HTTP::Server::Context
      @context.response.status_code = status_code
      @context.response.content_type = content_type if content_type
      @context
    end

    # Renders Plain with "text/plain" Content-Type.
    #
    # ```
    # class RenderPlain < BaseAction
    #   call do
    #     render_plain "Hello World!", status_code: 200
    #   end
    # end
    # ```
    def render_plain(text : String, *, status_code : Int32 = 200) : HTTP::Server::Context
      @context.response.content_type = "text/plain"
      @context.response.status_code = status_code
      @context.response.print text
      @context
    end

    # Renders Body with custom Content-Type.
    #
    # ```
    # class RenderBody < BaseAction
    #   call do
    #     render_body "Hello World!", content_type: "text/html", status_code: 200
    #   end
    # end
    # ```
    def render_body(body : String, *, status_code : Int32 = 200, content_type : String? = nil) : HTTP::Server::Context
      @context.response.content_type = content_type if content_type
      @context.response.status_code = status_code
      @context.response.print body
      @context
    end

    # Renders File.
    #
    # ```
    # class RenderFile < BaseAction
    #   call do
    #     render_file "public/robot.txt", status_code: 200, content_type: "text/plain", filename: "robot", disposition: "inline"
    #   end
    # end
    # ```
    def render_file(path : String, *, status_code : Int32 = 200, content_type : String?, filename : String? = nil, disposition : String = "attachment") : HTTP::Server::Context
      full_path = File.expand_path(path, Dir.current)
      @context.response.headers["Accept-Ranges"] = "bytes"
      @context.response.headers["X-Content-Type-Options"] = "nosniff"
      @context.response.headers["Content-Transfer-Encoding"] = "binary"
      @context.response.headers["Content-Disposition"] = filename ? "#{disposition}; filename=\"#{File.basename(filename)}\"" : disposition
      @context.response.content_type = content_type
      @context.response.content_length = File.size(full_path)
      @context.response.status_code = status_code
      File.open(full_path) { |file| IO.copy(file, @context.response.output) }
      @context
    end
  end
end
