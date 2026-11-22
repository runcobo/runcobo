require "../runcobo"

module Runcobo::Commands::RouteTables
  def self.generate_route_tables(routes = Runcobo::Action::ROUTES, *, color : Bool = false) : Array(String)
    rows = routes.map { |route| [cell(route.method), cell(route.url), cell(route.action)] }
    headers = ["METHOD", "PATH", "ACTION"]
    widths = headers.map_with_index { |header, index| rows.reduce(header.size) { |width, row| Math.max(width, row[index].size) } }
    lines = [style("Routes", "1", color), border(widths, "╭", "┬", "╮")]
    lines << row(headers, widths, color: color, header: true)
    lines << border(widths, "├", "┼", "┤")
    rows.each { |values| lines << row(values, widths, color: color) }
    lines << border(widths, "╰", "┴", "╯")
    lines << "#{rows.size} #{rows.size == 1 ? "route" : "routes"}"
    lines
  end

  private def self.cell(value : String) : String
    value.gsub(/[\x00-\x1f\x7f]/) { |character| character.inspect[1...-1] }
  end

  private def self.border(widths : Array(Int32), left : String, middle : String, right : String) : String
    left + widths.map { |width| "─" * (width + 2) }.join(middle) + right
  end

  private def self.row(values : Array(String), widths : Array(Int32), *, color : Bool, header : Bool = false) : String
    cells = values.map_with_index do |value, index|
      padded = value.ljust(widths[index])
      code = if header
               "1"
             elsif index == 0
               case value
               when "GET"             then "32"
               when "POST"            then "36"
               when "PUT", "PATCH"    then "33"
               when "DELETE"          then "31"
               when "HEAD", "OPTIONS" then "35"
               else                        "37"
               end
             end
      " " + (code ? style(padded, code, color) : padded) + " "
    end
    "│" + cells.join("│") + "│"
  end

  private def self.style(value : String, code : String, color : Bool) : String
    color ? "\e[#{code}m#{value}\e[0m" : value
  end
end
