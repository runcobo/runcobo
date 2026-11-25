require "./spec_helper"

module TaskSpec
  def self.routes_fixture(root : Path)
    Dir.mkdir(root / "src")
    Dir.mkdir(root / "lib")
    Dir.glob((ROOT / "lib/*").to_s).each do |dependency|
      File.symlink(dependency, root / "lib" / Path[dependency].basename)
    end
    File.symlink(ROOT, root / "lib/runcobo")
  end

  def self.route_command(root : Path, args = [] of String)
    Runcobo::Tasks::Runner.new.run((ROOT / "bin/cobo").to_s, ["--root", root.to_s, "routes"] + args,
      chdir: ROOT, capture: true, check: false)
  end
end

describe "cobo routes" do
  it "loads src/app.cr from the requested root without booting main or overwriting user files" do
    Runcobo::Tasks.temporary_directory("route-project-") do |root|
      TaskSpec.routes_fixture(root)
      File.write(root / "src/app.cr", <<-'CR')
require "runcobo"
class FixtureRoute < Runcobo::Action
  get "/widgets/:id"
  call do
    render_plain "unused"
  end
end
CR
      File.write(root / "src/main.cr", "raise \"The server entry must not be loaded\"\n")
      File.write(root / "__routes.cr", "user-owned file")
      result = TaskSpec.route_command(root)
      result.exit_code.should eq(0)
      result.output.should contain("METHOD")
      result.output.should contain("/widgets/:id")
      result.output.should contain("FixtureRoute")
      result.output.should contain("2 routes")
      result.output.should_not contain('\e')
      File.read(root / "__routes.cr").should eq("user-owned file")
      Dir.glob((root / ".cobo-routes-*.cr").to_s).should be_empty
    end
  end

  it "supports legacy route registration without database configuration" do
    Runcobo::Tasks.temporary_directory("route-project-") do |root|
      TaskSpec.routes_fixture(root)
      File.write(root / "src/runcobo.cr", "require \"runcobo\"\n")
      result = TaskSpec.route_command(root, ["--no-color"])
      result.exit_code.should eq(0)
      result.output.should contain("1 route")
      Dir.mkdir(root / "src/actions")
      File.write(root / "src/actions/legacy.cr", <<-'CR')
class LegacyFixtureRoute < Runcobo::Action
  get "/legacy"
  call do
    render_plain "unused"
  end
end
CR
      registered = TaskSpec.route_command(root)
      registered.exit_code.should eq(0)
      registered.output.should contain("/legacy")
      Dir.glob((root / ".cobo-routes-*.cr").to_s).should be_empty
    end
  end

  it "supports custom entry paths with spaces and explicit colors" do
    Runcobo::Tasks.temporary_directory("route-project-") do |root|
      TaskSpec.routes_fixture(root)
      File.write(root / "src/custom routes.cr", "require \"runcobo\"\n")
      result = TaskSpec.route_command(root, ["--require", "src/custom routes.cr", "--color"])
      result.exit_code.should eq(0)
      result.output.should contain("\e[1mRoutes\e[0m")
    end
  end

  it "reports missing entries and compilation errors and removes temporary files after failure" do
    Runcobo::Tasks.temporary_directory("route-project-") do |root|
      missing = TaskSpec.route_command(root)
      missing.exit_code.should_not eq(0)
      missing.error.should contain("--require FILE")
      Dir.children(root).should be_empty
      TaskSpec.routes_fixture(root)
      File.write(root / "src/app.cr", "UndefinedRouteFixtureConstant\n")
      failed = TaskSpec.route_command(root)
      failed.exit_code.should_not eq(0)
      failed.error.should contain("UndefinedRouteFixtureConstant")
      Dir.glob((root / ".cobo-routes-*.cr").to_s).should be_empty
      invalid = TaskSpec.route_command(root, ["extra"])
      invalid.exit_code.should_not eq(0)
      Dir.glob((root / ".cobo-routes-*.cr").to_s).should be_empty
    end
  end
end
