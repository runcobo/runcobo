require "uri"
require "http/params"
require "./config"
require "./support"
require "./migrations"

module Runcobo::Tasks
  class Database
    LOCAL_KINDS          = %w(development test)
    DEPLOYMENT_KINDS     = %w(staging production)
    SAFE_OPTIONS         = %w(application_name connect_timeout sslmode)
    DEPLOYMENT_OPTIONS   = SAFE_OPTIONS + %w(sslrootcert sslcert sslkey sslcrl target_session_attrs)
    CONNECTION_OVERRIDES = %w(PGHOST PGHOSTADDR PGPORT PGDATABASE PGSERVICE PGSERVICEFILE PGOPTIONS)
    getter settings : Config, runner : Runner

    def initialize(@settings : Config, @runner = Runner.new)
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
      raise ArgumentError.new("Unsupported local database kind") unless LOCAL_KINDS.includes?(kind)
      key = kind == "test" ? "TEST_DATABASE_URL" : "DEVELOPMENT_DATABASE_URL"
      value = environment[key]? || "#{managed}#{settings.database_prefix}_#{kind}"
      begin
        uri = URI.parse(value)
        valid = postgres_connection?(uri) && %w(127.0.0.1 localhost).includes?(uri.host) &&
                uri.path == "/#{settings.database_prefix}_#{kind}" && connection_options?(uri, SAFE_OPTIONS)
      rescue URI::Error | ArgumentError
        valid = false
      end
      raise ArgumentError.new("#{key} must identify the dedicated local #{settings.database_prefix}_#{kind} database without connection-target overrides") unless valid
      value
    end

    def self.validate_migration_kind(kind : String, operation : String)
      unless LOCAL_KINDS.includes?(kind) || DEPLOYMENT_KINDS.includes?(kind)
        raise ArgumentError.new("Expected a database environment: development, test, staging or production")
      end
      if kind == "production" && operation == "rollback"
        raise ArgumentError.new("Production rollback is not supported; apply a corrective migration")
      end
    end

    def migration_database_url(kind : String, operation : String, environment = ENV.to_h) : String
      Database.validate_migration_kind(kind, operation)
      return database_url(kind, environment) if LOCAL_KINDS.includes?(kind)

      key = kind == "staging" ? "STAGING_DATABASE_URL" : "PRODUCTION_DATABASE_URL"
      value = environment[key]?.try(&.presence) || raise ArgumentError.new("Set #{key} to the #{kind} database connection")
      begin
        uri = URI.parse(value)
        params = HTTP::Params.parse(uri.query || "")
        sslmode = params["sslmode"]?
        valid = postgres_connection?(uri) && !value.matches?(/[[:space:][:cntrl:]]|%(?![0-9a-fA-F]{2})/) &&
                !!uri.host.try(&.presence) && uri.path.matches?(/\A\/[^\/]+\z/) &&
                connection_options?(uri, DEPLOYMENT_OPTIONS) &&
                (sslmode.nil? || %w(disable allow prefer require verify-ca verify-full).includes?(sslmode))
      rescue URI::Error | ArgumentError
        valid = false
      end
      unless valid
        raise ArgumentError.new("#{key} must specify a PostgreSQL host and database without connection-target overrides")
      end
      return value if sslmode
      query = uri.not_nil!.query
      separator = query ? (query.empty? ? "" : "&") : "?"
      "#{value}#{separator}sslmode=verify-full"
    end

    private def postgres_connection?(uri : URI) : Bool
      %w(postgresql postgres).includes?(uri.scheme) && uri.fragment.nil? &&
        (uri.port.nil? || (1..65535).includes?(uri.port.not_nil!))
    end

    private def connection_options?(uri : URI, allowed : Array(String)) : Bool
      query = uri.query || ""
      return true if query.empty?
      return false unless query.split('&').all? { |pair| pair.includes?('=') && !/%(?![0-9a-fA-F]{2})/.matches?(pair) }

      names = Set(String).new
      HTTP::Params.parse(query).each do |name, _|
        return false unless allowed.includes?(name) && names.add?(name)
      end
      true
    end

    def connection_environment(environment = ENV.to_h) : Hash(String, String)
      environment.reject { |key, _| CONNECTION_OVERRIDES.includes?(key) }
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
        runner.run("pg_ctl", ["-D", data.to_s, "-l", (local / "postgres.log").to_s, "-o", "-h 127.0.0.1 -p #{settings.database_port} -k #{Process.quote(socket.to_s)}", "start"])
      end
    end

    def stop
      marker = local / "postgres-owner"
      raise ArgumentError.new("Unknown database cluster") unless File.exists?(marker) && File.read(marker) == "#{settings.name}\n"
      runner.run("pg_ctl", ["-D", (local / "postgres").to_s, "stop"])
    end

    def migrate(kind : String, options = Migrations::Options.new)
      Migrations.new(self).run(migration_database_url(kind, "migrate"), "migrate", options)
    end

    def status(kind : String, options = Migrations::Options.new)
      Migrations.new(self).status(migration_database_url(kind, "status"), options)
    end

    def wait(kind : String, options = Migrations::Options.new)
      Migrations.new(self).execute(migration_database_url(kind, "wait"), nil, "wait", options)
    end

    def console(kind : String)
      url = database_url(kind)
      environment = connection_environment
      if credentials = /\A(postgres(?:ql)?:\/\/[^:\/@]*):([^\/@]*)@/.match(url)
        environment["PGPASSWORD"] = URI.decode(credentials[2])
        url = url.sub(credentials[0], credentials[1] + "@")
      end
      runner.run("psql", ["-X", "--dbname", url], env: environment, chdir: settings.root, input: Process::Redirect::Inherit)
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

    def rollback(kind : String, options = Migrations::Options.new)
      Migrations.new(self).run(migration_database_url(kind, "rollback"), "rollback", options)
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
