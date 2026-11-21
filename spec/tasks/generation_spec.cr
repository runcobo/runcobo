require "./spec_helper"

module TaskSpec
  def self.generation_fixture(root : Path)
    %w(bin db/queries db/migrations db/rollbacks src/persistence/generated).each { |path| Dir.mkdir_p(root / path) }
    FileUtils.cp(ROOT / "bin/crsql", root / "bin/crsql")
    File.chmod(root / "bin/crsql", 0o755)
    File.write(root / "bin/crsql.toolchain", Runcobo::Tasks::Codegen::TOOLCHAIN)
    File.write(root / "Makefile", "bin/crsql:\n\ttest -x bin/crsql\n")
    FileUtils.cp(ROOT / "spec/tasks/fixtures/sqlc.yaml", root / "sqlc.yaml")
    File.write(root / "db/migrations/20261120082720_create_widgets.sql", "CREATE TABLE widgets (id bigint PRIMARY KEY, title text NOT NULL);\n")
    File.write(root / "db/rollbacks/20261120082720_drop_widgets.sql", "DROP TABLE widgets;\n")
    File.write(root / "db/queries/widgets.sql", "-- name: CreateWidget :one\nINSERT INTO widgets (id, title) VALUES (sqlc.arg(id), sqlc.arg(title)) RETURNING *;\n")
    File.write(root / "src/persistence/manual.cr", "# Handwritten helper must be preserved.\n")
  end
end

describe Runcobo::Tasks::Codegen do
  it "generates native queries without modifying sources or handwritten code" do
    Runcobo::Tasks.temporary_directory("native-generation-") do |root|
      TaskSpec.generation_fixture(root)
      before = TaskSpec.snapshot(root)
      checker = Runcobo::Tasks::Codegen.new(TaskSpec.settings(root))
      Runcobo::Tasks.temporary_directory("native-output-") do |destination|
        checker.generate(destination)
        generated = File.read(destination / "src/persistence/generated/queries.cr")
        generated.should contain("def create_widget(*, id : Int64, title : String)")
        generated.should contain("struct WidgetsRow")
        File.exists?(destination / "src/persistence/manual.cr").should be_false
        TaskSpec.snapshot(root).should eq(before)
        FileUtils.cp(destination / "src/persistence/generated/queries.cr", root / "src/persistence/generated/queries.cr")
      end
      ready = TaskSpec.snapshot(root)
      checker.check
      TaskSpec.snapshot(root).should eq(ready)
    end
  end

  it "adds fields from later migrations and ignores both rollback and reference snapshots" do
    Runcobo::Tasks.temporary_directory("native-generation-") do |root|
      TaskSpec.generation_fixture(root)
      File.write(root / "db/migrations/20261121082720_add_description.sql", "ALTER TABLE widgets ADD COLUMN description text;\n")
      File.write(root / "db/rollbacks/20261121082720_remove_description.sql", "ALTER TABLE widgets DROP COLUMN description;\n")
      File.write(root / "db/schema.snapshot.sql", "invalid snapshot; DROP TABLE widgets;\n")
      before = TaskSpec.snapshot(root)
      Runcobo::Tasks.temporary_directory("native-output-") do |destination|
        Runcobo::Tasks::Codegen.new(TaskSpec.settings(root)).generate(destination)
        File.read(destination / "src/persistence/generated/queries.cr").should contain("getter description : String?")
        File.exists?(destination / "db/schema.snapshot.sql").should be_false
        Dir.exists?(destination / "db/rollbacks").should be_false
      end
      TaskSpec.snapshot(root).should eq(before)
    end
  end

  it "preserves all reviewed files after generation failure or output mismatch" do
    Runcobo::Tasks.temporary_directory("native-generation-") do |root|
      TaskSpec.generation_fixture(root)
      generated = root / "src/persistence/generated/queries.cr"
      File.write(generated, "reviewed generated code")
      before = TaskSpec.snapshot(root)
      checker = Runcobo::Tasks::Codegen.new(TaskSpec.settings(root))
      expect_raises(ArgumentError, "Generated content differed") { checker.check }
      TaskSpec.snapshot(root).should eq(before)
      File.write(root / "db/queries/widgets.sql", "-- name: GetWidget :one\nSELECT missing_column FROM widgets;\n")
      invalid = TaskSpec.snapshot(root)
      expect_raises(Runcobo::Tasks::CommandError) { checker.check }
      TaskSpec.snapshot(root).should eq(invalid)
    end
  end

  it "removes its temporary directory after a partial generation failure" do
    Runcobo::Tasks.temporary_directory("native-generation-") do |root|
      TaskSpec.generation_fixture(root)
      destinations = [] of Path
      runner = TaskSpec::FakeRunner.new
      runner.handler = ->(call : TaskSpec::Call) do
        if call[:command].ends_with?("bin/crsql")
          destination = call[:chdir].not_nil!
          destinations << destination
          File.write(destination / "src/persistence/generated/partial.cr", "incomplete")
          Runcobo::Tasks::Result.new(1)
        else
          Runcobo::Tasks::Result.new(0)
        end
      end
      before = TaskSpec.snapshot(root)
      expect_raises(Runcobo::Tasks::CommandError) { Runcobo::Tasks::Codegen.new(TaskSpec.settings(root), runner).check }
      destinations.size.should eq(1)
      destinations.each { |path| Dir.exists?(path).should be_false }
      TaskSpec.snapshot(root).should eq(before)
    end
  end
end
