require "option_parser"
require "./runcobo/version"
require "./commands/*"

module Runcobo
  module Cli
    def self.display_help_and_exit(opts)
      puts <<-HELP
        runcobo [<commands>...] [<arguments>...]

        Commands:
          init [<project_name>]       - Initialize a runcobo project.
          routes                      - Print all routes of the app.
          version                     - Print the current version of the runcobo.
          help                        - Print usage synopsis.

        Options:
      HELP
      puts opts
      exit
    end

    def self.display_version_and_exit
      puts "Runcobo #{Runcobo::VERSION}"
      exit
    end

    def self.run
      path = Dir.current
      OptionParser.parse(ARGV) do |opts|
        opts.on("-h", "--help", "Print usage synopsis.") { self.display_help_and_exit(opts) }
        opts.on("-v", "--version", "Print the current version of the runcobo.") { self.display_version_and_exit }
        opts.unknown_args do |args, options|
          case args[0]?
          when "init"
            if args[1]?
              project_name = args[1]
              Runcobo::Commands::Init.run(path, project_name)
            else
              puts "[Error]Missing project_name"
              puts "init [<project_name>]       - Initialize a runcobo project."
              exit 1
            end
          when "routes"
            Runcobo::Commands::Routes.run(path)
          when "version"
            display_version_and_exit
          else
            display_help_and_exit(opts)
          end
        end
      end
    end
  end
end

begin
  Runcobo::Cli.run
rescue ex : OptionParser::InvalidOption
  puts ex.message
  exit 1
end
