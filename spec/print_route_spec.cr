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

  it "renders method, path and action columns without truncating long routes" do
    routes = [
      Runcobo::Route.new("GET", "/widgets/:id", "Widgets::Show"),
      Runcobo::Route.new("DELETE", "/widgets/:id/attachments/:attachment_id", "Widgets::Attachments::Delete"),
    ]
    lines = Runcobo::Commands::RouteTables.generate_route_tables(routes)
    lines[0].should eq("Routes")
    lines[2].should match(/METHOD.*PATH.*ACTION/)
    lines[4].should contain("/widgets/:id")
    lines[5].should contain("/widgets/:id/attachments/:attachment_id")
    lines[5].should contain("Widgets::Attachments::Delete")
    lines.last.should eq("2 routes")
    lines.join.should_not contain('\e')
    lines[1...-1].map(&.size).uniq.size.should eq(1)
    routes.first.url.should eq("/widgets/:id")
  end

  it "handles empty applications and colors methods only when requested" do
    empty = Runcobo::Commands::RouteTables.generate_route_tables([] of Runcobo::Route)
    empty.last.should eq("0 routes")
    route = [Runcobo::Route.new("GET", "/up", "Health")]
    plain = Runcobo::Commands::RouteTables.generate_route_tables(route)
    plain.last.should eq("1 route")
    colored = Runcobo::Commands::RouteTables.generate_route_tables(route, color: true)
    colored.join.should contain("\e[32m")
    colored.map { |line| line.gsub(/\e\[[0-9;]*m/, "") }.should eq(plain)
  end

  it "escapes control characters so route text cannot inject rows or terminal sequences" do
    routes = [Runcobo::Route.new("GET", "/one\n/two\e[31m", "Action\tName")]
    lines = Runcobo::Commands::RouteTables.generate_route_tables(routes)
    lines[4].should contain("\\n")
    lines[4].should_not contain('\n')
    lines.join.should_not contain('\e')
  end
end
