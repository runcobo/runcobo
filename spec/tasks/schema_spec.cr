require "./spec_helper"

describe Runcobo::Tasks::Schema do
  it "cleans up the temporary schema after a dbmate error" do
    Runcobo::Tasks.temporary_directory("verify-error-") do |root|
      TaskSpec.migration(root)
      runner = TaskSpec::FakeRunner.new
      runner.handler = ->(call : TaskSpec::Call) do
        if call[:command] == "dbmate"
          Runcobo::Tasks::Result.new(1, error: "migration failed")
        else
          Runcobo::Tasks::Result.new(0)
        end
      end
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), runner)
      expect_raises(Runcobo::Tasks::CommandError, "migration failed") { Runcobo::Tasks::Schema.new(database).check }
      runner.calls.first[:args].last.should start_with(%(CREATE SCHEMA "cobo_verify_))
      runner.calls.last[:args].last.should eq(runner.calls.first[:args].last.sub("CREATE SCHEMA", "DROP SCHEMA") + " CASCADE")
    end
  end

  it "checks both directions for schema-local statements before opening the temporary schema" do
    Runcobo::Tasks.temporary_directory("verify-input-") do |root|
      TaskSpec.migration(root)
      rollback = root / "db/rollbacks/20261120082720_drop_sample.sql"
      File.write(rollback, "DROP TABLE public.sample;")
      runner = TaskSpec::FakeRunner.new
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), runner)
      expect_raises(ArgumentError, "schema-local") { Runcobo::Tasks::Schema.new(database).check }
      runner.calls.should be_empty
    end
  end
end

describe Runcobo::Tasks::SchemaSnapshot do
  it "does not replace a prior snapshot if dump or cleanup fails" do
    Runcobo::Tasks.temporary_directory("snapshot-spec-") do |root|
      TaskSpec.migration(root)
      output = root / "db/schema.snapshot.sql"
      File.write(output, "reviewed snapshot")
      %w(dump cleanup).each do |failure|
        runner = TaskSpec::FakeRunner.new
        runner.handler = ->(call : TaskSpec::Call) do
          failed = (failure == "dump" && call[:command] == "pg_dump") ||
                   (failure == "cleanup" && call[:args].last.starts_with?("DROP SCHEMA"))
          Runcobo::Tasks::Result.new(failed ? 1 : 0)
        end
        database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), runner)
        expect_raises(Runcobo::Tasks::CommandError) { Runcobo::Tasks::SchemaSnapshot.new(database).generate }
        File.read(output).should eq("reviewed snapshot")
        runner.calls.last[:args].last.should start_with("DROP SCHEMA")
      end
    end
  end

  it "leaves a destination intact and removes partial output after publish failure" do
    Runcobo::Tasks.temporary_directory("snapshot-spec-") do |root|
      destination = root / "existing"
      Dir.mkdir(destination)
      File.write(destination / "sentinel", "preserved")
      expect_raises(File::Error) { Runcobo::Tasks.atomic_write(destination, "new snapshot", 0o444) }
      File.read(destination / "sentinel").should eq("preserved")
      Dir.children(root).should eq(["existing"])
    end
  end
end
