require "./spec_helper"

describe Runcobo::Tasks::Schema do
  it "always cleans its owned namespace after a failed replay" do
    database = Runcobo::Tasks::Database.new(TaskSpec.settings(TaskSpec::ROOT), TaskSpec::FakeRunner.new)
    schema = TaskSpec::FakeSchema.new(database)
    expect_raises(Exception, "comparison failed") do
      schema.replay(database.database_url("test"), [] of Path) { raise "comparison failed" }
    end
    schema.statements.first.should match(/\ACREATE SCHEMA "sample_verify_[a-f0-9]{32}"\z/)
    schema.statements.last.should eq(schema.statements.first.sub("CREATE SCHEMA", "DROP SCHEMA") + " CASCADE")
  end

  it "rejects statements escaping its namespace before any database statement" do
    Runcobo::Tasks.temporary_directory("replay-spec-") do |root|
      path = TaskSpec.migration(root)
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), TaskSpec::FakeRunner.new)
      schema = TaskSpec::FakeSchema.new(database)
      ["public.users", %q("public".users)].each do |table|
        File.write(path, "ALTER TABLE #{table} ADD COLUMN example text;")
        expect_raises(ArgumentError, "schema-local") { schema.replay("local-test", [path]) { true } }
      end
      schema.statements.should be_empty
    end
  end

  it "identifies structure differences" do
    database = Runcobo::Tasks::Database.new(TaskSpec.settings(TaskSpec::ROOT))
    schema = Runcobo::Tasks::Schema.new(database)
    expect_raises(ArgumentError, "indexes") do
      schema.assert_same(JSON.parse(%q({"columns": [], "indexes": ["expected"]})), JSON.parse(%q({"columns": [], "indexes": []})), "Replay")
    end
  end

  it "checks migration, rollback and replay only within its temporary namespace" do
    Runcobo::Tasks.temporary_directory("replay-spec-") do |root|
      TaskSpec.migration(root)
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), TaskSpec::FakeRunner.new)
      schema = TaskSpec::FakeSchema.new(database, IO::Memory.new)
      before = JSON.parse(%q({"relations": []}))
      after = JSON.parse(%q({"relations": ["sample"]}))
      schema.fingerprints = [before, after, before, after]
      schema.check
      schema.statements.size.should eq(6)
      schema.statements[2].should contain("CREATE TABLE sample")
      schema.statements[3].should contain("DROP TABLE sample")
      schema.statements[4].should contain("CREATE TABLE sample")
      schema.statements.last.should start_with("DROP SCHEMA")
      schema.statements.each { |sql| sql.should_not contain("SET search_path TO public") }
    end
  end

  it "reports an incorrect rollback and cleans without reapplying" do
    Runcobo::Tasks.temporary_directory("replay-spec-") do |root|
      TaskSpec.migration(root)
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), TaskSpec::FakeRunner.new)
      schema = TaskSpec::FakeSchema.new(database, IO::Memory.new)
      schema.fingerprints = [JSON.parse(%q({"columns": []})), JSON.parse(%q({"columns": ["id"]})), JSON.parse(%q({"columns": ["leftover"]}))]
      expect_raises(ArgumentError, "Rollback 20261120082720") { schema.check }
      schema.statements.size.should eq(5)
      schema.statements.last.should start_with("DROP SCHEMA")
    end
  end

  it "reports an incorrect reapplication and cleans the namespace" do
    Runcobo::Tasks.temporary_directory("replay-spec-") do |root|
      TaskSpec.migration(root)
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), TaskSpec::FakeRunner.new)
      schema = TaskSpec::FakeSchema.new(database, IO::Memory.new)
      before = JSON.parse(%q({"columns": []}))
      schema.fingerprints = [before, JSON.parse(%q({"columns": ["id"]})), before, JSON.parse(%q({"columns": ["different"]}))]
      expect_raises(ArgumentError, "Replay 20261120082720") { schema.check }
      schema.statements.last.should start_with("DROP SCHEMA")
    end
  end

  it "requires exactly one rollback before opening the temporary namespace" do
    Runcobo::Tasks.temporary_directory("replay-spec-") do |root|
      TaskSpec.migration(root)
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), TaskSpec::FakeRunner.new)
      schema = TaskSpec::FakeSchema.new(database, IO::Memory.new)
      rollback = root / "db/rollbacks/20261120082720_drop_sample.sql"
      File.delete(rollback)
      expect_raises(ArgumentError, "reviewed rollback") { schema.check }
      File.write(rollback, "DROP TABLE sample;")
      File.write(rollback.parent / "20261120082720_duplicate.sql", "DROP TABLE sample;")
      expect_raises(ArgumentError, "reviewed rollback") { schema.check }
      schema.statements.should be_empty
    end
  end

  it "checks later migrations after restoring the previous schema" do
    Runcobo::Tasks.temporary_directory("replay-spec-") do |root|
      TaskSpec.migration(root)
      path = TaskSpec.migration(root, "20261121082720", "later")
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), TaskSpec::FakeRunner.new)
      schema = TaskSpec::FakeSchema.new(database, IO::Memory.new)
      empty, first, second = ["[]", %q(["sample"]), %q(["sample", "later"])].map { |value| JSON.parse(%({"relations": #{value}})) }
      schema.fingerprints = [empty, first, empty, first, first, second, first, second]
      schema.check
      schema.statements[5].should contain(File.read(path))
      schema.statements.size.should eq(9)
    end
  end
end

describe Runcobo::Tasks::SchemaSnapshot do
  it "exports only replayed structure with no connection overrides and replaces a read-only file" do
    Runcobo::Tasks.temporary_directory("snapshot-spec-") do |root|
      path = TaskSpec.migration(root)
      runner = TaskSpec::FakeRunner.new
      runner.handler = ->(call : TaskSpec::Call) do
        name = call[:args][call[:args].index("--schema").not_nil! + 1]
        Runcobo::Tasks::Result.new(0, "CREATE TABLE #{name}.sample (id bigint);\nCOMMENT ON TABLE #{name}.sample IS '测试表';\n")
      end
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), runner)
      schema = TaskSpec::FakeSchema.new(database)
      snapshot = Runcobo::Tasks::SchemaSnapshot.new(database, schema, IO::Memory.new)
      output = root / database.settings.snapshot_path
      File.write(output, "old snapshot")
      File.chmod(output, 0o444)
      snapshot.generate.should eq(output)
      snapshot.generate
      source = File.read(output)
      source.should contain("DO NOT EDIT")
      source.should contain("CREATE TABLE public.sample")
      source.should contain("测试表")
      source.should_not contain("sample_verify_")
      (File.info(output).permissions.value & 0o222).should eq(0)
      runner.calls.size.should eq(2)
      runner.calls.each do |call|
        call[:args].should contain("--schema-only")
        call[:args].should contain("--no-owner")
        call[:args].should contain("--no-privileges")
        call[:args].should contain(database.database_url("test"))
        call[:env].not_nil!.has_key?("PGHOST").should be_false
      end
      File.read(path).should contain("CREATE TABLE sample")
      schema.statements.last.should start_with("DROP SCHEMA")
    end
  end

  it "preserves an existing snapshot and cleans its namespace when export fails" do
    Runcobo::Tasks.temporary_directory("snapshot-spec-") do |root|
      TaskSpec.migration(root)
      runner = TaskSpec::FakeRunner.new
      runner.handler = ->(call : TaskSpec::Call) { Runcobo::Tasks::Result.new(1, error: "export failed") }
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), runner)
      schema = TaskSpec::FakeSchema.new(database)
      output = root / database.settings.snapshot_path
      File.write(output, "reviewed snapshot")
      expect_raises(Runcobo::Tasks::CommandError) { Runcobo::Tasks::SchemaSnapshot.new(database, schema).generate }
      File.read(output).should eq("reviewed snapshot")
      schema.statements.last.should start_with("DROP SCHEMA")
      Dir.glob((output.parent / ".schema.snapshot.*.tmp").to_s).should be_empty
    end
  end

  it "does not publish when namespace cleanup fails" do
    Runcobo::Tasks.temporary_directory("snapshot-spec-") do |root|
      TaskSpec.migration(root)
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), TaskSpec::FakeRunner.new)
      schema = TaskSpec::FakeSchema.new(database)
      schema.cleanup_error = true
      output = root / database.settings.snapshot_path
      File.write(output, "reviewed snapshot")
      expect_raises(IO::Error, "cleanup failed") { Runcobo::Tasks::SchemaSnapshot.new(database, schema).generate }
      File.read(output).should eq("reviewed snapshot")
    end
  end

  it "leaves a destination intact and removes partial output after publish failure" do
    Runcobo::Tasks.temporary_directory("snapshot-spec-") do |root|
      destination = root / "existing"
      Dir.mkdir(destination)
      File.write(destination / "sentinel", "preserved")
      expect_raises(File::Error) { Runcobo::Tasks.atomic_write(destination, "new snapshot", 0o444) }
      File.read(destination / "sentinel").should eq("preserved")
      Dir.glob((root / ".existing.*.tmp").to_s).should be_empty
    end
  end

  it "rejects an empty migration directory without exporting" do
    Runcobo::Tasks.temporary_directory("snapshot-spec-") do |root|
      Dir.mkdir(root / "db")
      runner = TaskSpec::FakeRunner.new
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), runner)
      expect_raises(ArgumentError, "No migrations") { Runcobo::Tasks::SchemaSnapshot.new(database).generate }
      runner.calls.should be_empty
    end
  end
end
