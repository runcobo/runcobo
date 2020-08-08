require "jbuilder"
require "water"

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

    # Renders Water with "text/html" Content-Type.
    #
    # Option `layout`, the layout default to nil
    # Option `status_code`, rewrite status code for response, default to 200
    # Option `dir`, rewrite dir of file, default to "src/views/"
    # Option `layout_dir`, rewrite dir of layout, default to "src/views/layouts/"
    #
    # `src/views/layouts/application.water` must be present.
    # `src/views/renders/example.water` must be present.
    # ```
    # class RenderWater < BaseAction
    #   layout "application"
    #
    #   call do
    #     render_water "renders/example", status_code: 200
    #   end
    # end
    # ```
    macro render_water(filename, *, layout = "", status_code = 200, dir = "src/views/", layout_dir = "src/views/layouts/")
      @context.response.content_type = "text/html"
      @context.response.status_code = {{ status_code }}
      {% layout_file = layout == "" ? LAYOUT : layout %}
      {% if layout_file == "" %}
        Water.embed("{{dir.id}}{{filename.id}}.water", @context.response.output)
      {% else %}
        Water.embed("{{dir.id}}{{filename.id}}.water", @context.response.output, "{{layout_dir.id}}{{layout_file.id}}.water")
      {% end %}
      @context
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
    macro render_jbuilder(filename, *, layout = "", status_code = 200, dir = "src/views/", layout_dir = "src/views/layouts/")
      @context.response.content_type = "application/json"
      @context.response.status_code = {{ status_code }}
      {% layout_file = layout == "" ? LAYOUT : layout %}
      {% if layout_file == "" %}
        Jbuilder.embed("{{dir.id}}{{filename.id}}.jbuilder", @context.response.output)
      {% else %}
        Jbuilder.embed("{{dir.id}}{{filename.id}}.jbuilder", @context.response.output, "{{layout_dir.id}}{{layout_file.id}}.jbuilder")
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
