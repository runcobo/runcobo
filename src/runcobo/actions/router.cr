require "../structs/route"

module Runcobo
  module Router
    macro extended
      # Radix Tree for classes inheriated from `BaseAction`
      Tree = ::Radix::Tree(self.class).new

      # Route table
      @@routes : Array(Runcobo::Route) = [] of Runcobo::Route

      # Binds a route to current klass with method and url.
      # Uses `.get`,`.post`, `.delete`, `.put`, `.patch`, `.options`, `.head` instead.
      # Uses this method only when you want to add custom method, like "LINK", "UNLINK", "FIND", "PURGE" and etc.
      #
      # ```
      # class AddRouteExample < BaseAction
      #   add_route "LINK", "/example"
      #
      #   call do
      #     render_plain "Hello World!"
      #   end
      # end
      # ```
      def self.add_route(method : String, url : String) : Nil
        Tree.add("/#{method.upcase}#{url}", self)
        @@routes << Route.new(method.upcase, url, self.name)
      end

      # Reads route table.
      def self.routes : Array(Runcobo::Route)
        @@routes
      end

      # Adds GET URL to route table.
      # You can bind more than one route to one class.
      def self.get(url : String) : Nil
        add_route("GET", url)
      end

      # Adds POST URL to route table.
      def self.post(url : String) : Nil
        add_route("POST", url)
      end

      # Adds PUT URL to route table.
      def self.put(url : String) : Nil
        add_route("PUT", url)
      end

      # Adds DELETE URL to route table.
      def self.delete(url : String) : Nil
        add_route("DELETE", url)
      end

      # Adds PATCH URL to route table.
      def self.patch(url : String) : Nil
        add_route("PATCH", url)
      end

      # Adds OPTIONS URL to route table.
      def self.options(url : String) : Nil
        add_route("OPTIONS", url)
      end

      # Adds HEAD URL to route table.
      def self.head(url : String) : Nil
        add_route("HEAD", url)
      end
    end
  end
end
