require "../structs/route"

module Runcobo
  module Router
    # Binds a route to current klass with method and url.
    # Uses `.get`,`.post`, `.delete`, `.put`, `.patch`, `.options`, `.head` instead.
    # Uses this method only when you want to add custom method, like "LINK", "UNLINK", "FIND", "PURGE" and etc.
    #
    # ```
    # class AddRouteExample < BaseAction
    #   route "LINK", "/example"
    #
    #   call do
    #     render_plain "Hello World!"
    #   end
    # end
    # ```
    def route(method : String, url : String)
      raise "URL must start with /" unless url.starts_with?("/")
      add_route(method, url, self)
    end

    # Adds GET URL to route table.
    # You can bind more than one route to one class.
    def get(url : String) : Nil
      route("GET", url)
    end

    # Adds POST URL to route table.
    def post(url : String) : Nil
      route("POST", url)
    end

    # Adds PUT URL to route table.
    def put(url : String) : Nil
      route("PUT", url)
    end

    # Adds DELETE URL to route table.
    def delete(url : String) : Nil
      route("DELETE", url)
    end

    # Adds PATCH URL to route table.
    def patch(url : String) : Nil
      route("PATCH", url)
    end

    # Adds OPTIONS URL to route table.
    def options(url : String) : Nil
      route("OPTIONS", url)
    end

    # Adds HEAD URL to route table.
    def head(url : String) : Nil
      route("HEAD", url)
    end

    private def add_route(method : String, url : String, klass : Runcobo::Action.class) : Nil
      Runcobo::Action::TREE.add("/#{method.upcase}#{url}", klass)
      Runcobo::Action::ROUTES << Route.new(method.upcase, url, klass.name)
    end
  end
end
