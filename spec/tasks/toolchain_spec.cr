require "./spec_helper"

describe "default crsql toolchain" do
  it "installs the pinned private generator separately from application dependencies, builds once and forwards arguments" do
    Runcobo::Tasks.temporary_directory("toolchain-") do |root|
      runner = TaskSpec::FakeRunner.new
      runner.handler = ->(call : TaskSpec::Call) do
        if call[:command] == "crystal"
          File.write(call[:args].last, "compiled generator")
        end
        Runcobo::Tasks::Result.new(0)
      end
      generator = Runcobo::Tasks::Codegen.new(TaskSpec.settings(root), runner)
      generator.run(["version"])
      cache = root / ".local/runcobo/codegen"
      File.read(cache / "shard.yml").should eq(Runcobo::Tasks::Codegen::MANIFEST)
      File.read(cache / "shard.lock").should eq(Runcobo::Tasks::Codegen::LOCK)
      runner.calls.first[:args].should eq(["install", "--production"])
      runner.calls.first[:chdir].should eq(cache)
      runner.calls.last[:command].should eq((root / "bin/crsql").to_s)
      runner.calls.last[:args].should eq(["version"])
      File.exists?(root / "shard.yml").should be_false
      File.exists?(root / "shard.lock").should be_false
      runner.calls.clear
      generator.build
      runner.calls.should be_empty
      # A framework toolchain update invalidates the cached generator.
      File.write(generator.stamp, "old toolchain")
      generator.build
      runner.calls.size.should eq(2)
    end
  end

  it "keeps the previous executable and stamp when compilation fails and permits retry" do
    Runcobo::Tasks.temporary_directory("toolchain-") do |root|
      Dir.mkdir(root / "bin")
      File.write(root / "bin/crsql", "previous executable")
      File.write(root / "bin/crsql.toolchain", "previous toolchain")
      runner = TaskSpec::FakeRunner.new
      runner.handler = ->(call : TaskSpec::Call) { Runcobo::Tasks::Result.new(call[:command] == "crystal" ? 9 : 0) }
      generator = Runcobo::Tasks::Codegen.new(TaskSpec.settings(root), runner)
      expect_raises(Runcobo::Tasks::CommandError) { generator.build }
      File.read(generator.binary).should eq("previous executable")
      File.read(generator.stamp).should eq("previous toolchain")
      Dir.glob((root / "bin/.crsql.*").to_s).should be_empty
      runner.handler = ->(call : TaskSpec::Call) { Runcobo::Tasks::Result.new(0) }
      generator.build
      generator.current?.should be_true
    end
  end
end
