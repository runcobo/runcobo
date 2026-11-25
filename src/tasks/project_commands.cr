require "./server"

module Runcobo::Tasks
  class ProjectCommands
    def initialize(@database : Database, @output : IO = STDOUT)
    end

    def list_tasks
      tasks = @database.settings.tasks
      return @output.puts("No project tasks configured.") if tasks.empty?

      tasks.keys.sort.each do |name|
        description = tasks[name].description
        @output.puts(description.empty? ? name : "#{name}\t#{description}")
      end
    end

    def run_task(name : String, arguments : Array(String))
      task = @database.settings.tasks[name]? || raise ArgumentError.new("Unknown project task: #{name}")
      command = task.command.first?.try(&.presence) || raise ArgumentError.new("Project task #{name} has no command")
      run_development(command, task.command[1..] + arguments)
    end

    def test(arguments : Array(String), *, prepare : Bool)
      environment = @database.connection_environment
      url = @database.database_url("test", environment)
      @database.prepare("test") if prepare
      environment["DATABASE_URL"] = url
      environment["TEST_DATABASE_URL"] = url
      @database.runner.run("crystal", ["spec"] + arguments, env: environment, chdir: @database.settings.root,
        input: Process::Redirect::Inherit)
    end

    def runner(file : String, arguments : Array(String))
      script = source_file(file)
      if entry = application_entry
        with_script([entry, script]) do |path|
          run_development("crystal", ["run", path, "--"] + arguments)
        end
      else
        run_development("crystal", ["run", script.to_s, "--"] + arguments)
      end
    end

    def console
      if entry = application_entry
        with_script([entry], prelude: true) do |path|
          environment = development_environment
          result = @database.runner.run("crystal", ["env", "CRYSTAL_PATH"], env: environment,
            chdir: @database.settings.root, capture: true)
          environment["CRYSTAL_PATH"] = [File.dirname(path), result.output.strip].join(Process::PATH_DELIMITER)
          run_development("crystal", ["i", "--prelude", File.basename(path, ".cr")], environment)
        end
      else
        run_development("crystal", ["i"])
      end
    end

    private def development_environment
      Server.new(@database).environment(@database.connection_environment)
    end

    private def run_development(command : String, arguments : Array(String), environment = development_environment)
      @database.runner.run(command, arguments, env: environment, chdir: @database.settings.root,
        input: Process::Redirect::Inherit)
    end

    private def application_entry : Path?
      if configured = @database.settings.application_entry
        source_file(configured)
      else
        path = @database.settings.root / "src/app.cr"
        path if File.file?(path)
      end
    end

    private def source_file(file : String) : Path
      path = Path[file].expand(@database.settings.root)
      raise ArgumentError.new("Crystal source file not found: #{file}") unless path.extension == ".cr" && File.file?(path)
      path
    end

    private def with_script(files : Array(Path), *, prelude : Bool = false, &)
      root = @database.settings.root
      # Crystal looks up a custom prelude by name on its source search path.
      prefix = prelude ? "cobo-console-" : ".cobo-run-"
      temporary = File.tempfile(prefix, ".cr", dir: root.to_s)
      begin
        temporary.puts(%(require "prelude")) if prelude
        files.uniq.each { |file| temporary.puts("require #{("./" + file.relative_to(root).to_s).inspect}") }
        temporary.close
        yield temporary.path
      ensure
        temporary.close unless temporary.closed?
        File.delete?(temporary.path)
      end
    end
  end
end
