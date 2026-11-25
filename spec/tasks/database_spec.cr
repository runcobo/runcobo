require "./spec_helper"

describe Runcobo::Tasks::Database do
  it "accepts only the same independent local database targets as application tests" do
    examples = JSON.parse(File.read(TaskSpec::ROOT / "spec/tasks/fixtures/database_urls.json")).as_a
    database = Runcobo::Tasks::Database.new(TaskSpec.settings(TaskSpec::ROOT))
    examples.each do |example|
      environment = {"TEST_DATABASE_URL" => example["url"].as_s, "DATABASE_URL" => "postgresql://remote/production"}
      if example["allowed"].as_bool
        database.database_url("test", environment).should eq(example["url"].as_s)
      else
        expect_raises(ArgumentError) { database.database_url("test", environment) }
      end
    end
  end

  it "uses injected project names and ports rather than application constants" do
    settings = Runcobo::Tasks::Config.new(Path["/tmp/example"], "example", "example", "tester", 55678)
    database = Runcobo::Tasks::Database.new(settings)
    database.database_url("test", {} of String => String).should eq("postgresql://tester@127.0.0.1:55678/example_test")
    expect_raises(ArgumentError) { database.database_url("test", {"TEST_DATABASE_URL" => "postgresql://localhost/sample_test"}) }
    database.connection_environment({"PGHOST" => "remote", "PGDATABASE" => "production", "PATH" => "/bin", "PGPASSWORD" => "fixture"}).should eq({"PATH" => "/bin", "PGPASSWORD" => "fixture"})
  end

  it "rejects duplicate and invalid migration versions" do
    Runcobo::Tasks.temporary_directory("migration-spec-") do |root|
      path = TaskSpec.migration(root)
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root))
      File.write(path.parent / "20261120082720_duplicate.sql", "")
      expect_raises(ArgumentError, "Duplicate migration version") { Runcobo::Tasks::Migrations.new(database).files }
      File.delete(path.parent / "20261120082720_duplicate.sql")
      File.write(path.parent / "invalid.sql", "")
      expect_raises(ArgumentError, "Invalid migration name") { Runcobo::Tasks::Migrations.new(database).files }
    end
  end

  it "requires an ownership marker before managing an existing cluster" do
    Runcobo::Tasks.temporary_directory("cluster-spec-") do |root|
      Dir.mkdir_p(root / ".local/postgres")
      File.write(root / ".local/postgres/PG_VERSION", "14")
      runner = TaskSpec::FakeRunner.new
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), runner)
      expect_raises(ArgumentError, "ownership marker") { database.start }
      expect_raises(ArgumentError, "Unknown database cluster") { database.stop }
      runner.calls.should be_empty
    end
  end

  it "runs dbmate for both directions while staging legacy files without changing them" do
    Runcobo::Tasks.temporary_directory("migration-command-") do |root|
      path = TaskSpec.migration(root)
      original = File.read(path)
      native = path.parent / "20261121082720_native.sql"
      File.write(native, "-- migrate:up\nSELECT 1;\n-- migrate:down\nSELECT 2;\n")
      runner = TaskSpec::FakeRunner.new
      runner.handler = ->(call : TaskSpec::Call) do
        directory = Path[call[:args][call[:args].index("--migrations-dir").not_nil! + 1]]
        File.read(directory / path.basename).should eq("-- migrate:up\n#{original}\n-- migrate:down\nDROP TABLE sample;\n\n")
        File.read(directory / native.basename).should eq(File.read(native))
        Runcobo::Tasks::Result.new(0)
      end
      settings = TaskSpec.settings(root)
      database = Runcobo::Tasks::Database.new(settings, runner)
      database.migrate("test")
      database.rollback("test")
      runner.calls.map { |call| call[:args][-2] }.should eq(%w(migrate rollback))
      runner.calls.each do |call|
        call[:command].should eq("dbmate")
        call[:args].should contain("--migration-lock")
        call[:args].should contain("--no-dump-schema")
        call[:args].should contain("--strict")
        call[:args].should contain("/dev/null")
        call[:env].not_nil!["DATABASE_URL"].should eq(database.database_url("test") + "?sslmode=#{ENV["PGSSLMODE"]? || "prefer"}")
        call[:env].not_nil!.has_key?("PGHOST").should be_false
      end
      File.read(path).should eq(original)
    end
  end
end

class PreparationObservingDatabase < Runcobo::Tasks::Database
  getter steps = [] of String

  def ensure_database(kind : String) : String
    steps << "ensure"
    database_url(kind)
  end

  def migrate(kind : String)
    steps << "migrate"
  end
end

describe "migration preparation" do
  it "prepares by provisioning before applying migrations" do
    database = PreparationObservingDatabase.new(TaskSpec.settings(TaskSpec::ROOT))
    database.prepare("test")
    database.steps.should eq(%w(ensure migrate))
  end
end
