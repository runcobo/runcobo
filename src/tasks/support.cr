require "json"
require "file_utils"
require "digest/sha256"
require "random/secure"
require "uuid"
require "set"

module Runcobo::Tasks
  class CommandError < Exception
    getter exit_code : Int32

    def initialize(command : String, @exit_code : Int32, details : String = "")
      super("#{command} failed (status #{exit_code})#{details.empty? ? "" : ": #{details.strip}"}")
    end
  end

  record Result, exit_code : Int32, output : String = "", error : String = ""

  class Runner
    def run(command : String, args : Array(String) = [] of String, *, env : Hash(String, String)? = nil, chdir : Path? = nil, capture : Bool = false, quiet : Bool = false, check : Bool = true) : Result
      output = IO::Memory.new
      error = IO::Memory.new
      status = Process.run(command, args, env: env, clear_env: !env.nil?, chdir: chdir,
        output: capture ? output : quiet ? Process::Redirect::Close : STDOUT,
        error: capture || quiet ? error : STDERR)
      result = Result.new(status.exit_code, output.to_s, error.to_s)
      raise CommandError.new(command, status.exit_code, result.error) if check && !status.success?
      result
    end
  end

  def self.temporary_directory(prefix : String, &)
    path = Path[Dir.tempdir] / "#{prefix}#{UUID.random}"
    Dir.mkdir(path, 0o700)
    begin
      yield path
    ensure
      FileUtils.rm_rf(path) if Dir.exists?(path)
    end
  end

  def self.atomic_write(path : Path, source : String, permissions = 0o644)
    temporary = File.tempfile(".#{path.basename}.", ".tmp", dir: path.parent.to_s)
    begin
      temporary.print(source)
      temporary.close
      File.chmod(temporary.path, permissions)
      File.rename(temporary.path, path)
    ensure
      temporary.close unless temporary.closed?
      File.delete(temporary.path) if File.exists?(temporary.path)
    end
  end
end
