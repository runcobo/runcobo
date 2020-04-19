require "file_utils"

module Runcobo
  # A module to print route table to console.
  module Commands::Routes
    # A piece of to-execute codes to print route table.
    ROUTES = <<-END
      require "./src/runcobo"
      require "./src/actions/**"
      Runcobo::Commands::RouteTables.execute
      END

    # Runs path
    def self.run(path)
      tempfile = File.open("__routes.cr", "w+")
      tempfile.print(ROUTES)
      tempfile.flush
      status = Process.run("crystal", ["run", tempfile.path], output: STDOUT, error: STDERR)
      tempfile.delete
      exit status.exit_code
    end
  end
end
