require "./spec_helper"

describe Runcobo::Tasks::Runner do
  it "preserves child exit codes and diagnostics without invoking a shell" do
    result = Runcobo::Tasks::Runner.new.run("sh", ["-c", "printf failure >&2; exit 7"], capture: true, check: false)
    result.exit_code.should eq(7)
    result.error.should eq("failure")
    error = expect_raises(Runcobo::Tasks::CommandError) { Runcobo::Tasks::Runner.new.run("sh", ["-c", "exit 7"], capture: true) }
    error.exit_code.should eq(7)
  end
end

describe Runcobo::Tasks::Server do
  it "creates a private local secret once and honors inherited development settings" do
    Runcobo::Tasks.temporary_directory("development-spec-") do |root|
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root))
      development = Runcobo::Tasks::Server.new(database)
      inherited = {"HOST" => "127.0.0.1", "PORT" => "3999", "PUBLIC_BASE_URL" => "https://example.test"}
      first = development.environment(inherited)
      secret = root / ".local/development-secret"
      first["JWT_SECRET"].should eq(File.read(secret))
      File.info(secret).permissions.value.should eq(0o600)
      development.environment(inherited)["JWT_SECRET"].should eq(first["JWT_SECRET"])
      first["PORT"].should eq("3999")
      first["PUBLIC_BASE_URL"].should eq("https://example.test")
      first["DATABASE_URL"].should eq(database.database_url("development"))
      inherited.has_key?("JWT_SECRET").should be_false
    end
  end

  it "can be reused by an application without JWT secrets or seed commands" do
    Runcobo::Tasks.temporary_directory("development-spec-") do |root|
      settings = Runcobo::Tasks::Config.new(root, "sample", "sample", "sample", 55888)
      runner = TaskSpec::FakeRunner.new
      database = Runcobo::Tasks::Database.new(settings, runner)
      environment = Runcobo::Tasks::Server.new(database).environment({} of String => String)
      environment.keys.should eq(["DATABASE_URL"])
      File.exists?(root / ".local/development-secret").should be_false
      database.seed("development")
      runner.calls.should be_empty
    end
  end
end

it "can compile database tooling without loading application or command code" do
  Runcobo::Tasks::Runner.new.run("crystal", ["build", "--no-codegen", (TaskSpec::ROOT / "spec/tasks/fixtures/database_import.cr").to_s], capture: true)
end

it "does not import development tasks through the framework runtime" do
  Runcobo::Tasks::Runner.new.run("crystal", ["build", "--no-codegen", (TaskSpec::ROOT / "spec/tasks/fixtures/runtime_import.cr").to_s], capture: true)
end
