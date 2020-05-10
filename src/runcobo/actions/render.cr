require "jbuilder"

module Runcobo
  module Render
    # Set layout, support many Template Engines.
    #
    # `src/views/layouts/application.jbuilder` must be present.
    # `src/views/example.jbuilder` must be present.
    #
    # ```
    # class Layout < BaseAction
    #   layout "application"
    #
    #   call do
    #     render_jbuilder "example"
    #   end
    # end
    # ```
    macro layout(filename)
      LAYOUT = {{ filename }}
    end

    # Renders Jbuilder with "application/json" Content-Type.
    #
    # `src/views/layouts/application.jbuilder` must be present.
    # `src/views/renders/example.jbuilder` must be present.
    # ```
    # class RenderJbuilder < BaseAction
    #   layout "application"
    #
    #   call do
    #     render_jbuilder "renders/example", status_code: 200
    #   end
    # end
    # ```
    macro render_jbuilder(filename, *, layout = nil, status_code = 200, dir = true)
      @context.response.content_type = "application/json"
      @context.response.status_code = {{ status_code }}
      {% real_layout = layout || LAYOUT %}
      {% if dir %}
        {% if !real_layout.id %}
          Jbuilder.embed("src/views/{{filename.id}}.jbuilder", @context.response.output, "src/views/layouts/{{real_layout.id}}.jbuilder")
        {% else %}
          Jbuilder.embed("src/views/{{filename.id}}.jbuilder", @context.response.output)
        {% end %}
      {% else %}
        {% if !real_layout.id %}
          Jbuilder.embed("{{filename.id}}.jbuilder", @context.response.output, "{{real_layout.id}}.jbuilder")
        {% else %}
          Jbuilder.embed("{{filename.id}}.jbuilder", @context.response.output)
        {% end %}
      {% end %}
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
