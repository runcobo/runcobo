require "./runcobo/version"
require "./commands/*"
require "./tasks"

module Runcobo::Cli
  def self.run(arguments = ARGV)
    case arguments.first?
    when "--version", "-v", "version"
      raise ArgumentError.new("Unexpected arguments") unless arguments.size == 1
      puts "Runcobo #{Runcobo::VERSION}"
    when nil, "--help", "-h", "help"
      puts "Usage: cobo [--root PATH] COMMAND [arguments...]"
      puts "  routes                      Print application routes"
      puts "  version                     Print the framework version"
      puts Tasks::Command::HELP
    when "routes"
      raise ArgumentError.new("Unexpected arguments") unless arguments.size == 1
      Commands::Routes.run(Dir.current)
    else
      Tasks::Command.run(arguments)
    end
  end
end

begin
  Runcobo::Cli.run
rescue ex
  STDERR.puts(ex.message)
  exit(ex.is_a?(Runcobo::Tasks::CommandError) && ex.exit_code > 0 ? ex.exit_code : 1)
end
