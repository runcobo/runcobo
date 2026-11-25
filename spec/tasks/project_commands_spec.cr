require "./spec_helper"

private class ProjectTestDatabase < Runcobo::Tasks::Database
  getter preparations = [] of String

  def prepare(kind : String)
    @preparations << kind
  end
end

describe Runcobo::Tasks::ProjectCommands do
  it "discovers and runs configured tasks from the project root with arguments, input and exit status" do
    Runcobo::Tasks.temporary_directory("cobo-project-") do |root|
      File.write(root / "runcobo.yml", <<-YAML)
        name: example
        database_prefix: example
        database_user: tester
        database_port: 55439
        tasks:
          report:
            description: Print the local report
            command: [sh, report.sh, fixed]
        YAML
      File.write(root / "report.sh", <<-'SH')
        IFS= read -r line
        printf '%s\n' "$@" "$line" "${DATABASE_URL##*/}"
        exit 7
        SH
      executable = (TaskSpec::ROOT / "bin/cobo").to_s
      runner = Runcobo::Tasks::Runner.new
      env = ENV.to_h.merge({"DEVELOPMENT_DATABASE_URL" => "postgresql://localhost/example_development"})
      list = runner.run(executable, ["--root", root.to_s, "task", "list"], env: env, capture: true)
      list.output.should eq("report\tPrint the local report\n")

      result = runner.run(executable, ["--root", root.to_s, "task", "run", "report", "--", "--literal", "two words"],
        env: env, input: IO::Memory.new("from stdin\n"), capture: true, check: false)
      result.output.lines.should eq(["fixed", "--literal", "two words", "from stdin", "example_development"])
      result.exit_code.should eq(7)

      unknown = runner.run(executable, ["task", "run", "unknown"], chdir: root, capture: true, check: false)
      unknown.error.should contain("Unknown project task: unknown")
    end
  end

  it "loads the application before running a script and cleans the temporary entry file on failure" do
    Runcobo::Tasks.temporary_directory("cobo-runner-") do |root|
      File.write(root / "runcobo.yml", <<-YAML)
        name: example
        database_prefix: example
        database_user: tester
        database_port: 55439
        application_entry: boot.cr
        YAML
      File.write(root / "boot.cr", "COBO_RUNNER_FIXTURE = \"loaded\"\n")
      File.write(root / "task script.cr", "puts COBO_RUNNER_FIXTURE; puts ARGV.first; exit 9\n")
      executable = (TaskSpec::ROOT / "bin/cobo").to_s
      env = ENV.to_h.merge({"DEVELOPMENT_DATABASE_URL" => "postgresql://localhost/example_development"})
      result = Runcobo::Tasks::Runner.new.run(executable, ["runner", "task script.cr", "--", "with spaces"],
        chdir: root, env: env, capture: true, check: false)
      result.output.lines.should eq(["loaded", "with spaces"])
      result.exit_code.should eq(9)
      Dir.children(root).none?(&.starts_with?(".cobo-run-")).should be_true
    end
  end

  it "optionally prepares the test database before running specs and forwards their arguments" do
    runner = TaskSpec::FakeRunner.new
    database = ProjectTestDatabase.new(TaskSpec.settings(TaskSpec::ROOT), runner)
    project = Runcobo::Tasks::ProjectCommands.new(database)
    project.test(["spec/models", "--", "--verbose"], prepare: false)
    database.preparations.should be_empty
    project.test(["spec/models", "--", "--verbose"], prepare: true)
    database.preparations.should eq(["test"])
    call = runner.calls.last
    call[:command].should eq("crystal")
    call[:args].should eq(["spec", "spec/models", "--", "--verbose"])
    call[:env].not_nil!["DATABASE_URL"].should eq(database.database_url("test"))
    call[:env].not_nil!["TEST_DATABASE_URL"].should eq(database.database_url("test"))
  end
end
