require "./spec_helper"

class PrintRouteSpec < BaseAction
  get "/print_route"
  call do
    render_plain "PRINT_ROUTE"
  end
end

describe "PrintRoute" do
  it "print_route" do
    Runcobo::Commands::RouteTables.generate_route_tables.join.should contain "PrintRouteSpec"
  end
end
