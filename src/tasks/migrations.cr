module Runcobo::Tasks
  class Migrations
    TABLE = "schema_migrations"

    record Options, global_args : Array(String) = [] of String, command_args : Array(String) = [] of String

    def initialize(@database : Database)
    end

    def files : Array(Path)
      settings = @database.settings
      versions = Set(String).new
      Dir.glob((settings.root / settings.migration_directory / "*.sql").to_s).sort.map do |name|
        path = Path[name]
        match = /\A(\d{14})_.+\.sql\z/.match(path.basename)
        raise ArgumentError.new("Invalid migration name: #{path.basename}") unless match
        raise ArgumentError.new("Duplicate migration version: #{match[1]}") unless versions.add?(match[1])
        path
      end
    end

    def run(url : String, operation : String, options = Options.new)
      Runcobo::Tasks.temporary_directory("cobo-migrations-") do |directory|
        files.each { |path| stage(directory, path) }
        execute(url, directory, operation, options)
      end
    end

    def status(url : String, options = Options.new)
      # dbmate only needs the filenames to compare versions. This also lets
      # developers inspect pending migrations before writing their rollback.
      Runcobo::Tasks.temporary_directory("cobo-status-") do |directory|
        files.each { |path| File.write(directory / path.basename, "") }
        execute(url, directory, "status", options)
      end
    end

    def stage(directory : Path, path : Path, *, schema_local : Bool = false)
      source = File.read(path)
      unless source.lchop('\u{FEFF}').matches?(/^--\s*migrate:(?:up|down)\b/m)
        settings = @database.settings
        version = path.basename.split('_', 2).first
        rollbacks = Dir.glob((settings.root / settings.rollback_directory / "#{version}_*.sql").to_s)
        raise ArgumentError.new("A reviewed rollback file is required for #{version}") unless rollbacks.size == 1
        rollback = File.read(rollbacks.first)
        source = "-- migrate:up\n#{source.lchop('\u{FEFF}')}\n-- migrate:down\n#{rollback.lchop('\u{FEFF}')}\n"
      end
      if schema_local && source.matches?(/\bpublic"?\s*\.|\b(?:CREATE|DROP|ALTER)\s+SCHEMA\b|\bSET\s+(?:LOCAL\s+)?search_path\b|^\s*\\/im)
        raise ArgumentError.new("Schema replay requires unqualified, schema-local migration statements: #{path.basename}")
      end
      File.write(directory / path.basename, source)
    end

    def execute(url : String, directory : Path?, operation : String, options = Options.new)
      settings = @database.settings
      environment = @database.connection_environment.reject { |key, _| key.starts_with?("DBMATE_") }
      # Preserve the original encoding of credentials and connection options
      # when appending a default connection mode for local databases.
      query = URI.parse(url).query
      unless HTTP::Params.parse(query || "").has_key?("sslmode")
        mode = URI.encode_www_form(environment["PGSSLMODE"]? || "prefer")
        separator = query ? (query.empty? ? "" : "&") : "?"
        url = "#{url}#{separator}sslmode=#{mode}"
      end
      environment["DATABASE_URL"] = url
      dbmate = if executable = Process.executable_path
                 Process.find_executable(File.join(File.dirname(executable), "runcobo-dbmate"))
               end
      begin
        args = ["--env-file", "/dev/null", "--migrations-table", TABLE, "--no-dump-schema"]
        args.concat(["--migrations-dir", directory.to_s]) if directory
        args << "--migration-lock" if operation.in?("migrate", "rollback")
        args.concat(options.global_args)
        args << operation
        args << "--strict" unless operation == "wait"
        args.concat(options.command_args)
        @database.runner.run(dbmate || "dbmate", args, chdir: settings.root, env: environment, check: operation != "status")
      rescue error : IO::Error
        raise error if dbmate || Process.find_executable("dbmate", path: environment["PATH"]?, pwd: settings.root)
        raise ArgumentError.new("dbmate was not found. Run make install or install dbmate 2.38.2 or later on PATH")
      end
    end
  end
end
