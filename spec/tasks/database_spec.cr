require "./spec_helper"

class LockObservingDatabase < Runcobo::Tasks::Database
  getter operations = [] of String

  def observe(url : String, operation : String)
    File.open(lock_path(url), "a") do |file|
      expect_raises(IO::Error) { file.flock_exclusive(false) }
    end
    operations << operation
  end

  def migrate_locked(url : String)
    observe(url, "migrate")
  end

  def rollback_locked(url : String)
    observe(url, "rollback")
  end
end

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

  it "rejects changed and missing applied migrations before writing" do
    Runcobo::Tasks.temporary_directory("migration-spec-") do |root|
      path = TaskSpec.migration(root)
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root))
      files = database.migration_files
      applied = {"20261120082720" => database.checksum(path)}
      database.check_ledger(files, applied)
      File.write(path, "changed")
      expect_raises(ArgumentError, "checksum changed") { database.check_ledger(files, applied) }
      expect_raises(ArgumentError, "file is missing") { database.check_ledger({} of String => Path, applied) }
    end
  end

  it "rejects duplicate and invalid migration versions" do
    Runcobo::Tasks.temporary_directory("migration-spec-") do |root|
      path = TaskSpec.migration(root)
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root))
      File.write(path.parent / "20261120082720_duplicate.sql", "")
      expect_raises(ArgumentError, "Duplicate migration version") { database.migration_files }
      File.delete(path.parent / "20261120082720_duplicate.sql")
      File.write(path.parent / "invalid.sql", "")
      expect_raises(ArgumentError, "Invalid migration name") { database.migration_files }
    end
  end

  it "holds one shared lock throughout migration and rollback and releases it afterwards" do
    Runcobo::Tasks.temporary_directory("lock-spec-") do |root|
      database = LockObservingDatabase.new(TaskSpec.settings(root))
      database.migrate("test")
      database.rollback("test")
      database.operations.should eq(%w(migrate rollback))
      database.migration_lock(database.database_url("test")) { true }.should be_true
    end
  end

  it "serializes separate processes across loopback aliases and worktrees" do
    Runcobo::Tasks.temporary_directory("lock-process-") do |root|
      executable = root / "lock-probe"
      runner = Runcobo::Tasks::Runner.new
      runner.run("crystal", ["build", (TaskSpec::ROOT / "spec/tasks/fixtures/lock_probe.cr").to_s, "-o", executable.to_s], capture: true)
      ready = root / "ready"
      acquired = root / "acquired"
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root))
      child = nil
      reaped = false
      begin
        database.migration_lock("postgresql://127.0.0.1:55439/sample_test") do
          child = Process.new(executable.to_s, [root.to_s, ready.to_s, acquired.to_s])
          TaskSpec.wait_until { File.exists?(ready) }
          sleep 0.1.seconds
          File.exists?(acquired).should be_false
        end
        TaskSpec.wait_until { child.not_nil!.terminated? }
        status = child.not_nil!.wait
        reaped = true
        status.success?.should be_true
        File.exists?(acquired).should be_true
      ensure
        if process = child
          process.signal(Signal::KILL) unless process.terminated?
          process.wait unless reaped
        end
      end
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

  it "uses a single database transaction for each migration and matching ledger write" do
    Runcobo::Tasks.temporary_directory("migration-command-") do |root|
      TaskSpec.migration(root)
      runner = TaskSpec::FakeRunner.new
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), runner, IO::Memory.new)
      database.migrate("test")
      write = runner.calls.find { |call| call[:args].includes?("--single-transaction") }.not_nil!
      write[:args].join(' ').should contain("INSERT INTO schema_migrations")
      write[:args].should contain("--file")
      write[:env].not_nil!.keys.should_not contain("PGHOST")
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

describe "migration preparation and legacy ledger adoption" do
  it "prepares by provisioning before applying migrations" do
    database = PreparationObservingDatabase.new(TaskSpec.settings(TaskSpec::ROOT))
    database.prepare("test")
    database.steps.should eq(%w(ensure migrate))
  end

  it "adopts old checksums only after comparing the actual schema to migration replay" do
    Runcobo::Tasks.temporary_directory("ledger-spec-") do |root|
      path = TaskSpec.migration(root)
      runner = TaskSpec::FakeRunner.new
      runner.handler = ->(call : TaskSpec::Call) do
        source = call[:args].last
        output = if source.includes?("SELECT version ||")
                   "20261120082720|\n"
                 elsif source.includes?("SELECT jsonb_build_object")
                   %({"relations": ["sample"]})
                 else
                   ""
                 end
        Runcobo::Tasks::Result.new(0, output)
      end
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), runner, IO::Memory.new)
      database.migration_ledger(database.database_url("test"), database.migration_files)
      statements = runner.calls.map { |call| call[:args].last }
      statements.count { |source| source.includes?("SELECT jsonb_build_object") }.should eq(2)
      statements.any? { |source| source.includes?("UPDATE schema_migrations SET checksum='#{database.checksum(path)}'") }.should be_true
      statements.any? { |source| source.starts_with?("DROP SCHEMA") }.should be_true
    end
  end

  it "does not adopt checksums when the existing schema differs" do
    Runcobo::Tasks.temporary_directory("ledger-spec-") do |root|
      TaskSpec.migration(root)
      runner = TaskSpec::FakeRunner.new
      fingerprint_calls = 0
      runner.handler = ->(call : TaskSpec::Call) do
        source = call[:args].last
        output = if source.includes?("SELECT version ||")
                   "20261120082720|\n"
                 elsif source.includes?("SELECT jsonb_build_object")
                   fingerprint_calls += 1
                   fingerprint_calls == 1 ? %({"relations": ["sample"]}) : %({"relations": []})
                 else
                   ""
                 end
        Runcobo::Tasks::Result.new(0, output)
      end
      database = Runcobo::Tasks::Database.new(TaskSpec.settings(root), runner, IO::Memory.new)
      expect_raises(ArgumentError, "Cannot adopt checksums") { database.migration_ledger(database.database_url("test"), database.migration_files) }
      statements = runner.calls.map { |call| call[:args].last }
      statements.any? { |source| source.includes?("UPDATE schema_migrations") }.should be_false
      statements.last.should start_with("DROP SCHEMA")
    end
  end
end
