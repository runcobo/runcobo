require "uri"
require "http/params"
require "./config"
require "./support"

module Runcobo::Tasks
  class Database
    SAFE_OPTIONS         = %w(application_name connect_timeout sslmode)
    CONNECTION_OVERRIDES = %w(PGHOST PGHOSTADDR PGPORT PGDATABASE PGSERVICE PGSERVICEFILE PGOPTIONS)
    getter settings : Config, runner : Runner

    def initialize(@settings : Config, @runner = Runner.new, @output : IO = STDOUT)
      raise ArgumentError.new("Invalid database prefix") unless /\A[a-z_][a-z0-9_]*\z/.matches?(settings.database_prefix)
      raise ArgumentError.new("Invalid database port") unless (1..65535).includes?(settings.database_port)
    end

    def local : Path
      settings.root / ".local"
    end

    def managed : String
      "postgresql://#{settings.database_user}@127.0.0.1:#{settings.database_port}/"
    end

    def database_url(kind : String, environment = ENV.to_h) : String
      raise ArgumentError.new("Unsupported local database kind") unless %w(test development).includes?(kind)
      key = kind == "test" ? "TEST_DATABASE_URL" : "DEVELOPMENT_DATABASE_URL"
      value = environment[key]? || "#{managed}#{settings.database_prefix}_#{kind}"
      begin
        uri = URI.parse(value)
        names = Set(String).new
        query = uri.query || ""
        options_valid = query.empty? || query.split('&').all? do |pair|
          !pair.empty? && pair.includes?('=') && !/%(?![0-9a-fA-F]{2})/.matches?(pair)
        end
        HTTP::Params.parse(uri.query || "").each do |name, _|
          options_valid = false unless SAFE_OPTIONS.includes?(name) && names.add?(name)
        end
        valid = %w(postgresql postgres).includes?(uri.scheme) && %w(127.0.0.1 localhost).includes?(uri.host) &&
                uri.path == "/#{settings.database_prefix}_#{kind}" && uri.fragment.nil? &&
                (uri.port.nil? || (1..65535).includes?(uri.port.not_nil!)) && options_valid
      rescue URI::Error | ArgumentError
        valid = false
      end
      raise ArgumentError.new("#{key} must identify the dedicated local #{settings.database_prefix}_#{kind} database without connection-target overrides") unless valid
      value
    end

    def connection_environment(environment = ENV.to_h) : Hash(String, String)
      environment.reject { |key, _| CONNECTION_OVERRIDES.includes?(key) }
    end

    def lock_path(url : String) : Path
      uri = URI.parse(url)
      identity = "#{uri.port || 5432}:#{uri.path}"
      directory = Path[Dir.tempdir] / "#{settings.name}-migration-locks-#{LibC.getuid}"
      Dir.mkdir_p(directory, 0o700)
      directory / "#{Digest::SHA256.hexdigest(identity)}.lock"
    end

    def migration_lock(url : String, &)
      File.open(lock_path(url), "a") do |file|
        file.flock_exclusive { yield }
      end
    end

    def psql(url : String, source : String? = nil, *, capture : Bool = true) : Result
      args = ["-X", "--set=ON_ERROR_STOP=1", "--no-password", "--tuples-only", "--no-align", url]
      args.concat(["--command", source]) if source
      runner.run("psql", args, env: connection_environment, capture: capture, quiet: !capture)
    end

    def start
      data = local / "postgres"
      socket = local / "socket"
      marker = local / "postgres-owner"
      Dir.mkdir_p(socket)
      unless File.exists?(data / "PG_VERSION")
        Dir.mkdir_p(data)
        result = runner.run("initdb", ["-D", data.to_s, "-A", "trust", "-U", settings.database_user, "--no-locale", "-E", "UTF8"], capture: true)
        File.write(local / "initdb.log", result.output + result.error)
        File.write(marker, "#{settings.name}\n")
      end
      raise ArgumentError.new("Refusing to manage a database cluster without this project ownership marker") unless File.exists?(marker) && File.read(marker) == "#{settings.name}\n"
      status = runner.run("pg_ctl", ["-D", data.to_s, "status"], quiet: true, check: false)
      unless status.exit_code == 0
        runner.run("pg_ctl", ["-D", data.to_s, "-l", (local / "postgres.log").to_s, "-o", "-h 127.0.0.1 -p #{settings.database_port} -k #{socket}", "start"])
      end
    end

    def stop
      marker = local / "postgres-owner"
      raise ArgumentError.new("Unknown database cluster") unless File.exists?(marker) && File.read(marker) == "#{settings.name}\n"
      runner.run("pg_ctl", ["-D", (local / "postgres").to_s, "stop"])
    end

    def migration_files : Hash(String, Path)
      files = {} of String => Path
      Dir.glob((settings.root / settings.migration_directory / "*.sql").to_s).sort.each do |name|
        path = Path[name]
        version = path.basename.split('_', 2).first
        raise ArgumentError.new("Invalid migration name: #{path.basename}") unless /\A\d{14}\z/.matches?(version)
        raise ArgumentError.new("Duplicate migration version: #{version}") if files.has_key?(version)
        files[version] = path
      end
      files
    end

    def checksum(path : Path) : String
      Digest::SHA256.hexdigest(File.read(path))
    end

    def check_ledger(files : Hash(String, Path), applied : Hash(String, String))
      applied.each do |version, digest|
        path = files[version]? || raise ArgumentError.new("Applied migration file is missing: #{version}")
        if !digest.empty? && digest != checksum(path)
          raise ArgumentError.new("Applied migration checksum changed: #{path.basename}")
        end
      end
    end

    def migration_ledger(url : String, files : Hash(String, Path)) : Hash(String, String)
      psql(url, "CREATE TABLE IF NOT EXISTS schema_migrations (version varchar PRIMARY KEY, checksum varchar(64))", capture: false)
      psql(url, "ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS checksum varchar(64)", capture: false)
      applied = {} of String => String
      psql(url, "SELECT version || '|' || COALESCE(checksum,'') FROM schema_migrations").output.lines.each do |line|
        version, digest = line.split('|', 2)
        applied[version] = digest
      end
      check_ledger(files, applied)
      missing = applied.select { |_, digest| digest.empty? }.keys
      unless missing.empty?
        Schema.new(self).verify_existing(url, applied.keys.sort.map { |version| files[version] })
        updates = missing.map { |version| "UPDATE schema_migrations SET checksum='#{checksum(files[version])}' WHERE version='#{version}'" }
        psql(url, "BEGIN;#{updates.join(';')};COMMIT;", capture: false)
      end
      applied
    end

    def migrate(kind : String)
      url = database_url(kind)
      migration_lock(url) { migrate_locked(url) }
    end

    def migrate_locked(url : String)
      files = migration_files
      applied = migration_ledger(url, files)
      files.each do |version, path|
        next if applied.has_key?(version)
        runner.run("psql", ["-X", "--set=ON_ERROR_STOP=1", "--no-password", "--single-transaction", url, "--file", path.to_s, "--command", "INSERT INTO schema_migrations (version,checksum) VALUES ('#{version}','#{checksum(path)}')"], env: connection_environment, quiet: true)
        @output.puts "Applied #{path.basename}"
      end
    end

    def ensure_database(kind : String) : String
      url = database_url(kind)
      if url.starts_with?(managed)
        start
        name = "#{settings.database_prefix}_#{kind}"
        exists = psql(managed + "postgres", "SELECT 1 FROM pg_database WHERE datname='#{name}'").output.strip
        if exists.empty?
          runner.run("createdb", ["-h", "127.0.0.1", "-p", settings.database_port.to_s, "-U", settings.database_user, name], env: connection_environment)
        end
      end
      url
    end

    def prepare(kind : String)
      ensure_database(kind)
      migrate(kind)
    end

    def rollback(kind : String)
      url = database_url(kind)
      migration_lock(url) { rollback_locked(url) }
    end

    def rollback_locked(url : String)
      migration_ledger(url, migration_files)
      version = psql(url, "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1").output.strip
      return if version.empty?
      raise ArgumentError.new("Invalid recorded migration version") unless /\A\d{14}\z/.matches?(version)
      paths = Dir.glob((settings.root / settings.rollback_directory / "#{version}_*.sql").to_s)
      raise ArgumentError.new("A reviewed rollback file is required") unless paths.size == 1
      runner.run("psql", ["-X", "--set=ON_ERROR_STOP=1", "--no-password", "--single-transaction", url, "--file", paths.first, "--command", "DELETE FROM schema_migrations WHERE version='#{version}'"], env: connection_environment, quiet: true)
      @output.puts "Rolled back #{version}"
    end

    def seed(kind : String)
      environment = connection_environment
      environment["DATABASE_URL"] = database_url(kind)
      command = settings.seed_command
      return if command.empty?
      runner.run(command.first, command[1..], env: environment, chdir: settings.root)
    end
  end
end

# Ledger adoption verifies old schemas through the same migration replay implementation.
require "./schema"
