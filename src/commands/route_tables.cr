require "../runcobo"

module Runcobo
  module Commands::RouteTables
    def self.generate_route_tables : Array(String)
      current_routes = Runcobo::Action::ROUTES
      max_action_size = current_routes.max_by { |x| x.action.size }.action.size
      current_routes.map do |route|
        padding = " " * (max_action_size - route.action.size)
        row = [route.action, padding, "\t", route.method, "\t", route.url]
        row.join
      end
    end
  end
end
