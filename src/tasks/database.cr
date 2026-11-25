require "uri"
require "http/params"
require "./config"
require "./support"
require "./migrations"

module Runcobo::Tasks
  class Database
    SAFE_OPTIONS         = %w(application_name connect_timeout sslmode)
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

    def migrate(kind : String)
      Migrations.new(self).run(database_url(kind), "migrate")
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
      Migrations.new(self).run(database_url(kind), "rollback")
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
