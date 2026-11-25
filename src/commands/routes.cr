require "option_parser"
require "path"

module Runcobo::Commands::Routes
  HELP = "Usage: cobo [--root PATH] routes [--require FILE] [--color | --no-color]"

  def self.run(path : String | Path, arguments = [] of String) : Int32
    root = Path[path.to_s].expand
    entry = nil.as(String?)
    color = STDOUT.tty? && !ENV.has_key?("NO_COLOR") && ENV["TERM"]? != "dumb"
    help = false
    OptionParser.parse(arguments) do |options|
      options.banner = HELP
      options.on("--require FILE", "Load a route registration file instead of the default application entry") { |file| entry = file }
      options.on("--color", "Always use terminal colors") { color = true }
      options.on("--no-color", "Print without terminal colors") { color = false }
      options.on("-h", "--help", "Show route command usage") { help = true }
      options.unknown_args do |args|
        raise ArgumentError.new("Unexpected route arguments: #{args.join(" ")}") unless args.empty?
      end
    end
    if help
      puts HELP
      return 0
    end
    raise ArgumentError.new("Project directory does not exist: #{root}") unless Dir.exists?(root)
    source = if file = entry
               Path[file].expand(root)
             else
               %w(src/app.cr src/runcobo.cr).map { |file| root / file }.find { |file| File.file?(file) }
             end
    unless source && File.file?(source)
      raise ArgumentError.new("No route registration file found. Create src/app.cr or use cobo routes --require FILE; the file should register actions without starting the server.")
    end

    temporary = File.tempfile(".cobo-routes-", ".cr", dir: root.to_s)
    begin
      temporary.puts "require #{("./" + source.relative_to(root).to_s).inspect}"
      if entry.nil? && source == root / "src/runcobo.cr" && Dir.exists?(root / "src/actions")
        temporary.puts "require \"./src/actions/**\""
      end
      temporary.puts "Runcobo::Commands::RouteTables.generate_route_tables(color: #{color}).each { |line| puts line }"
      temporary.close
      Process.run("crystal", ["run", temporary.path], chdir: root.to_s, output: STDOUT, error: STDERR).exit_code
    ensure
      temporary.close unless temporary.closed?
      File.delete(temporary.path) if File.exists?(temporary.path)
    end
  end
end
