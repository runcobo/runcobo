require "../runcobo"

module Runcobo
  module Commands::RouteTables
    def self.execute
      current_routes = Runcobo::Action::ROUTES
      max_action_size = current_routes.max_by { |x| x.action.size }.action.size
      current_routes.each do |route|
        padding = " " * (max_action_size - route.action.size)
        row = [route.action, padding, "\t", route.method, "\t", route.url]
        puts row.join
      end
    end
  end
end
