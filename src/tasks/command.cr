module Runcobo::Tasks
  module Command
    HELP = <<-TEXT
      Project commands (configured in runcobo.yml):
        dev                         Prepare and start the development server
        db start|stop               Manage the owned local database cluster
        db ensure|prepare|migrate|rollback|seed [development|test]
        db verify                   Verify dbmate rollback and replay in the test database
        db snapshot                 Export a read-only structure reference from migrations
        db --help                   Show database commands and environment options
        generate                    Generate typed queries with crsql
        generate --check            Compare generated queries without rewriting project files
        crsql [arguments...]        Run the bundled development generator
        crsql-build                 Build the development generator without generating queries
      Options: --root PATH          Use another project directory
      TEXT

    DB_HELP = <<-TEXT
      Usage: cobo [--root PATH] db COMMAND [ENV]

      Database commands:
        start             Start the project's local PostgreSQL cluster
        stop              Stop the project's local PostgreSQL cluster
        ensure [ENV]      Start the managed cluster and create the selected database if needed
        prepare [ENV]     Run ensure, then apply pending migrations
        migrate [ENV]     Apply pending migrations to an existing database
        rollback [ENV]    Roll back the most recent migration
        seed [ENV]        Run the configured seed command
        verify            Check rollback and replay in a temporary schema in the test database
        snapshot          Export a read-only structure snapshot from migrations using the test database

      ENV is development (default) or test. verify and snapshot always use test.
      start and stop apply to the whole local cluster.
      Use prepare to provision a managed local database and migrate it.
      Use migrate when the database already exists. It does not create the database.
      An externally managed local database must already exist. Run seed separately to load seed data.
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
        if %w(verify snapshot).includes?(operation)
          raise ArgumentError.new("Unexpected arguments") unless args.empty?
        else
          raise ArgumentError.new("Unknown database operation: #{operation}") unless %w(start stop ensure prepare migrate rollback seed).includes?(operation)
          kind = args.shift? || "development"
          raise ArgumentError.new("Unsupported local database kind") unless %w(test development).includes?(kind)
          raise ArgumentError.new("Unexpected arguments") unless args.empty?
        end
        database = Database.new(Config.load(root))
        case operation
        when "start"    then database.start
        when "stop"     then database.stop
        when "ensure"   then database.ensure_database(kind.not_nil!)
        when "prepare"  then database.prepare(kind.not_nil!)
        when "migrate"  then database.migrate(kind.not_nil!)
        when "rollback" then database.rollback(kind.not_nil!)
        when "seed"     then database.seed(kind.not_nil!)
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
  end
end
