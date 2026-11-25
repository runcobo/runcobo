require "spec"
require "../../src/tasks"

module TaskSpec
  ROOT = Path[__DIR__].parent.parent
  alias Call = NamedTuple(command: String, args: Array(String), env: Hash(String, String)?, chdir: Path?, capture: Bool, quiet: Bool, check: Bool)

  class FakeRunner < Runcobo::Tasks::Runner
    getter calls = [] of Call
    property handler : Proc(Call, Runcobo::Tasks::Result) = ->(call : Call) { Runcobo::Tasks::Result.new(0) }

    def run(command : String, args : Array(String) = [] of String, *, env : Hash(String, String)? = nil, chdir : Path? = nil, capture : Bool = false, quiet : Bool = false, check : Bool = true) : Runcobo::Tasks::Result
      call = {command: command, args: args, env: env, chdir: chdir, capture: capture, quiet: quiet, check: check}
      calls << call
      result = handler.call(call)
      raise Runcobo::Tasks::CommandError.new(command, result.exit_code, result.error) if check && result.exit_code != 0
      result
    end
  end

  def self.settings(root : Path) : Runcobo::Tasks::Config
    Runcobo::Tasks::Config.new(root, "sample", "sample", "tester", 55439, secret_environment: "JWT_SECRET", seed_command: ["crystal", "run", "src/seed_main.cr"], development_environment: {"HOST" => "127.0.0.1", "PORT" => "3108"}, public_base_environment: "PUBLIC_BASE_URL")
  end

  def self.migration(root : Path, version = "20261120082720", name = "sample") : Path
    Dir.mkdir_p(root / "db/migrations")
    Dir.mkdir_p(root / "db/rollbacks")
    path = root / "db/migrations/#{version}_create_#{name}.sql"
    File.write(path, "CREATE TABLE #{name} (id bigint);\n")
    File.write(root / "db/rollbacks/#{version}_drop_#{name}.sql", "DROP TABLE #{name};\n")
    path
  end

  def self.snapshot(root : Path)
    Dir.glob((root / "**/*").to_s).select { |path| File.file?(path) }.to_h do |file|
      path = Path[file]
      {path.relative_to(root).to_s, {Digest::SHA256.hexdigest(File.read(path)), File.info(path).modification_time, File.info(path).permissions}}
    end
  end
end
