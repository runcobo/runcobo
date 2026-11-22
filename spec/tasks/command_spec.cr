require "./spec_helper"

describe Runcobo::Tasks::Config do
  it "loads project differences while preserving native migration and crsql defaults" do
    Runcobo::Tasks.temporary_directory("task-config-") do |root|
      File.write(root / "runcobo.yml", <<-YAML)
        name: example
        database_prefix: example
        database_user: tester
        database_port: 55678
        seed_command: [crystal, run, src/seed.cr]
        development_environment:
          PORT: "3456"
        YAML
      config = Runcobo::Tasks::Config.load(root)
      config.root.should eq(root)
      config.migration_directory.should eq("db/migrations")
      config.generator_config.should eq("sqlc.yaml")
      config.seed_command.should eq(["crystal", "run", "src/seed.cr"])
      config.development_environment["PORT"].should eq("3456")
      config.secret_environment.should be_nil
      File.write(root / "runcobo.yml", File.read(root / "runcobo.yml") + "database_prt: 1234\n")
      expect_raises(YAML::ParseException) { Runcobo::Tasks::Config.load(root) }
    end
  end
end

describe Runcobo::Tasks::Command do
  it "rejects invalid operations, kinds and trailing arguments before loading configuration or creating state" do
    Runcobo::Tasks.temporary_directory("task-command-") do |root|
      [["db", "migrate", "production"], ["db", "unknown"], ["db", "snapshot", "development"],
       ["generate", "--bad"], ["dev", "extra"], ["crsql-build", "extra"], ["unknown"]].each do |args|
        error = expect_raises(ArgumentError) { Runcobo::Tasks::Command.run(args, root) }
        error.message.not_nil!.should_not contain("runcobo.yml")
      end
      Dir.children(root).should be_empty
    end
  end

  it "provides help and version without project configuration and returns failure for unknown commands" do
    runner = Runcobo::Tasks::Runner.new
    Runcobo::Tasks.temporary_directory("task-command-") do |root|
      executable = (TaskSpec::ROOT / "bin/cobo").to_s
      help = runner.run(executable, ["--help"], chdir: root, capture: true).output
      help.should contain("Usage: cobo ")
      help.should contain("db snapshot")
      help.should contain("runcobo.yml")
      runner.run(executable, ["--version"], chdir: root, capture: true).output.should contain("Runcobo")
      runner.run(executable, ["--root", root.to_s, "db", "migrate", "production"], capture: true, check: false).exit_code.should eq(1)
      runner.run(executable, ["unknown"], chdir: root, capture: true, check: false).exit_code.should eq(1)
      Dir.children(root).should be_empty
    end
  end
end
