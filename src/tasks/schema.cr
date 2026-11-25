require "./database"

module Runcobo::Tasks
  class Schema
    def initialize(@database : Database, @output : IO = STDOUT)
      @migrations = Migrations.new(@database)
    end

    def replay(url : String, paths : Array(Path), &)
      Runcobo::Tasks.temporary_directory("cobo-schema-") do |directory|
        paths.each { |path| @migrations.stage(directory, path, schema_local: true) }
        with_schema(url) do |schema, replay_url|
          @migrations.execute(replay_url, directory, "migrate")
          yield schema
        end
      end
    end

    def dump(url : String, schema : String) : String
      result = @database.runner.run("pg_dump",
        ["--dbname", url, "--schema-only", "--schema", schema, "--exclude-table", "#{schema}.#{Migrations::TABLE}",
         "--no-owner", "--no-privileges", "--no-password", "--encoding=UTF8"],
        env: @database.connection_environment, capture: true)
      result.output
    end

    def check
      paths = @migrations.files
      url = @database.database_url("test")
      Runcobo::Tasks.temporary_directory("cobo-verify-") do |directory|
        # Validate and copy every input before opening the temporary schema.
        pending = directory / "pending"
        Dir.mkdir(pending)
        paths.each { |path| @migrations.stage(pending, path, schema_local: true) }
        with_schema(url) do |schema, replay_url|
          paths.each do |path|
            version = path.basename.split('_', 2).first
            before = structure(url, schema)
            File.rename(pending / path.basename, directory / path.basename)
            @migrations.execute(replay_url, directory, "migrate")
            after = structure(url, schema)
            @migrations.execute(replay_url, directory, "rollback")
            assert_same(before, structure(url, schema), "Rollback #{version}")
            @migrations.execute(replay_url, directory, "migrate")
            assert_same(after, structure(url, schema), "Replay #{version}")
          end
        end
      end
      @output.puts "Verified #{paths.size} migrations with rollback and replay."
    end

    private def with_schema(url : String, &)
      schema = "cobo_verify_#{UUID.random.to_s.delete('-')}"
      uri = URI.parse(url)
      params = HTTP::Params.parse(uri.query || "")
      params["search_path"] = schema
      uri.query = params.to_s
      @database.psql(url, %(CREATE SCHEMA "#{schema}"))
      begin
        yield schema, uri.to_s
      ensure
        @database.psql(url, %(DROP SCHEMA "#{schema}" CASCADE))
      end
    end

    private def structure(url : String, schema : String) : String
      source = dump(url, schema)
      # Updated pg_dump clients emit a new key for each dump. Match the paired
      # outer commands so their random value does not affect the comparison.
      if match = /\A((?:--[^\n]*\n|\r?\n)*)\\restrict ([a-zA-Z0-9]+)\r?\n/.match(source)
        source = source.sub(match[0], match[1])
        source = source.sub(/\\unrestrict #{match[2]}\r?\n(?=\s*\z)/, "")
      end
      source
    end

    private def assert_same(expected : String, actual : String, label : String)
      raise ArgumentError.new("#{label}: database schema differs") unless expected == actual
    end
  end
end
