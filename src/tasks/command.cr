require "option_parser"
require "./project_commands"

module Runcobo::Tasks
  module Command
    HELP = <<-TEXT
      Project commands (configured in runcobo.yml):
        dev                         Prepare and start the development server
        db start|stop               Manage the owned local database cluster
        db ensure|prepare|seed|console [development|test]
        db migrate|status|wait [development|test|staging|production]
        db rollback [development|test|staging]
        db verify                   Verify dbmate rollback and replay in the test database
        db snapshot                 Export a read-only structure reference from migrations
        db --help                   Show database commands and environment options
        task list                   List project tasks
        task run NAME [-- arguments...]   Run a configured project task
        test [--prepare] [arguments...]  Run Crystal specs with the local test database settings
        runner FILE [-- arguments...]    Run a Crystal script in the development environment
        console                     Open an interactive Crystal development console
        generate                    Generate typed queries with crsql
        generate --check            Compare generated queries without rewriting project files
        crsql [arguments...]        Run the bundled development generator
        crsql-build                 Build the development generator without generating queries
      Options: --root PATH          Use another project directory
      TEXT

    DB_HELP = <<-TEXT
      Usage: cobo [--root PATH] db COMMAND [ENV] [options]

      Database commands:
        start             Start the project's local PostgreSQL cluster
        stop              Stop the project's local PostgreSQL cluster
        ensure [ENV]      Start the managed cluster and create the selected database if needed
        prepare [ENV]     Run ensure, then apply pending migrations
        migrate [ENV]     Apply pending migrations to an existing database
        status [ENV]      Show applied, pending and missing migrations
        rollback [ENV]    Roll back the most recent migration
        wait [ENV]        Wait for the PostgreSQL server to become available
        seed [ENV]        Run the configured seed command
        console [ENV]     Open psql on the selected local database
        verify            Check rollback and replay in a temporary schema in the test database
        snapshot          Export a read-only structure snapshot from migrations using the test database

      ENV defaults to development. All commands with ENV accept development or test.
      migrate, status, rollback and wait also accept staging. Use STAGING_DATABASE_URL.
      migrate, status and wait also accept production. Use PRODUCTION_DATABASE_URL.
      verify and snapshot always use test.
      start and stop apply to the whole local cluster.
      Use prepare to provision a managed local database and migrate it.
      Use migrate when the database already exists. It does not create the database.
      An externally managed local database must already exist. Run seed separately to load seed data.
      status and console connect to an existing database without preparing it.
      Run cobo db migrate --help (or rollback, status, wait) for dbmate options.
      TEXT

    def self.run(arguments : Array(String), root = Path[Dir.current])
      args = arguments.dup
      if args.first? == "--root"
        args.shift
        root = Path[args.shift? || raise ArgumentError.new("--root requires a path")].expand
      end
      command = args.shift?
      return STDOUT.puts(HELP) if command.nil? || %w(--help -h help).includes?(command)
      case command
      when "db"
        operation = args.shift? || raise ArgumentError.new("db requires an operation")
        if %w(--help -h help).includes?(operation)
          raise ArgumentError.new("Unexpected arguments") unless args.empty?
          return STDOUT.puts(DB_HELP)
        end
        if %w(migrate rollback status wait).includes?(operation)
          return run_migration_command(operation, args, root)
        elsif %w(verify snapshot).includes?(operation)
          raise ArgumentError.new("Unexpected arguments") unless args.empty?
        else
          raise ArgumentError.new("Unknown database operation: #{operation}") unless %w(start stop ensure prepare seed console).includes?(operation)
          kind = args.shift? || "development"
          raise ArgumentError.new("Unsupported local database kind") unless Database::LOCAL_KINDS.includes?(kind)
          raise ArgumentError.new("Unexpected arguments") unless args.empty?
        end
        database = Database.new(Config.load(root))
        case operation
        when "start"   then database.start
        when "stop"    then database.stop
        when "ensure"  then database.ensure_database(kind.not_nil!)
        when "prepare" then database.prepare(kind.not_nil!)
        when "seed"    then database.seed(kind.not_nil!)
        when "console" then database.console(kind.not_nil!)
        when "verify"
          database.ensure_database("test")
          Schema.new(database).check
        when "snapshot"
          database.ensure_database("test")
          SchemaSnapshot.new(database).generate
        end
      when "dev"
        raise ArgumentError.new("Unexpected arguments") unless args.empty?
        Server.new(Database.new(Config.load(root))).run
      when "task"
        run_task_command(args, root)
      when "test"
        prepare = args.first? == "--prepare"
        args.shift if prepare
        project(root).test(args, prepare: prepare)
      when "runner"
        file = args.shift? || raise ArgumentError.new("Usage: cobo runner FILE [-- arguments...]")
        args.shift if args.first? == "--"
        project(root).runner(file, args)
      when "console"
        raise ArgumentError.new("Unexpected arguments") unless args.empty?
        project(root).console
      when "generate"
        raise ArgumentError.new("Unexpected arguments") unless args.empty? || args == ["--check"]
        generator = Codegen.new(Config.load(root))
        args.empty? ? generator.generate : generator.check
      when "crsql", "crsql-build"
        raise ArgumentError.new("Unexpected arguments") if command == "crsql-build" && !args.empty?
        generator = Codegen.new(Config.load(root))
        command == "crsql-build" ? generator.build : generator.run(args)
      else
        raise ArgumentError.new("Unknown command: #{command}")
      end
    end

    private def self.run_migration_command(operation : String, args : Array(String), root : Path)
      global_args = [] of String
      command_args = [] of String
      wait = false
      show_help = false
      environments = operation == "rollback" ? "development|test|staging" : "development|test|staging|production"
      parser = OptionParser.parse(args) do |options|
        options.banner = "Usage: cobo [--root PATH] db #{operation} [#{environments}] [options]"
        unless operation == "wait"
          options.on("--wait", "Wait for the PostgreSQL server first") { wait = true }
          options.on("--strict", "Enforce strict migration checks (already enabled)") { }
        end
        options.on("--wait-timeout TIME", "Maximum wait for the server (default 60s)") do |value|
          wait = true
          global_args << "--wait-timeout=#{value}"
        end
        options.on("--wait-interval TIME", "Time between connection attempts (default 1s)") do |value|
          wait = true
          global_args << "--wait-interval=#{value}"
        end
        if operation.in?("migrate", "rollback")
          options.on("-v", "--verbose", "Print the result of each migration statement") { command_args << "--verbose" }
          options.on("--migration-lock-timeout TIME", "Maximum wait for the migration lock (default 5m)") do |value|
            global_args << "--migration-lock-timeout=#{value}"
          end
          options.on("--migration-application-name", "Include the migration version in the connection's application name") do
            global_args << "--migration-application-name"
          end
        elsif operation == "status"
          options.on("--exit-code", "Exit with status 1 if there are pending migrations") { command_args << "--exit-code" }
          options.on("--quiet", "Suppress status output and imply --exit-code") { command_args << "--quiet" }
        end
        options.on("-h", "--help", "Show command help") { show_help = true }
        options.invalid_option { |option| raise ArgumentError.new("Unknown option for db #{operation}: #{option.split('=', 2).first}") }
        options.missing_option { |option| raise ArgumentError.new("Missing value for #{option}") }
      end
      return STDOUT.puts(parser) if show_help

      kind = args.shift? || "development"
      Database.validate_migration_kind(kind, operation)
      raise ArgumentError.new("Unexpected arguments") unless args.empty?
      global_args << "--wait" if wait && operation != "wait"
      options = Migrations::Options.new(global_args, command_args)
      database = Database.new(Config.load(root))
      case operation
      when "migrate"  then database.migrate(kind, options)
      when "rollback" then database.rollback(kind, options)
      when "status"   then database.status(kind, options)
      when "wait"     then database.wait(kind, options)
      end
    end

    private def self.project(root : Path) : ProjectCommands
      ProjectCommands.new(Database.new(Config.load(root)))
    end

    private def self.run_task_command(args : Array(String), root : Path)
      case operation = args.shift?
      when "--help", "-h", "help"
        raise ArgumentError.new("Unexpected arguments") unless args.empty?
        STDOUT.puts("Usage: cobo task list | cobo task run NAME [-- arguments...]")
      when "list"
        raise ArgumentError.new("Unexpected arguments") unless args.empty?
        project(root).list_tasks
      when "run"
        name = args.shift? || raise ArgumentError.new("task run requires a task name")
        args.shift if args.first? == "--"
        project(root).run_task(name, args)
      else
        raise ArgumentError.new("Unknown task operation: #{operation || "(missing)"}; see cobo task --help")
      end
    end
  end
end
