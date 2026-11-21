require "./config"
require "./support"

module Runcobo::Tasks
  class Codegen
    MANIFEST  = {{ read_file("#{__DIR__}/crsql.yml") }}
    LOCK      = {{ read_file("#{__DIR__}/crsql.lock") }}
    TOOLCHAIN = Digest::SHA256.hexdigest(MANIFEST + LOCK)

    def initialize(@settings : Config, @runner = Runner.new, @output : IO = STDOUT)
    end

    def binary : Path
      @settings.root / @settings.generator_binary
    end

    def stamp : Path
      Path[binary.to_s + ".toolchain"]
    end

    def current? : Bool
      return false unless File.file?(binary) && File.file?(stamp) && File.read(stamp) == TOOLCHAIN
      sources = Dir.glob((@settings.root / ".local/runcobo/codegen/lib/crsql/src/**/*.cr").to_s)
      sources.none? { |path| File.info(path).modification_time > File.info(binary).modification_time }
    end

    # The private generator is installed only when a development command needs it.
    # Application dependencies and runtime never load this toolchain.
    def build
      return if current?
      cache = @settings.root / ".local/runcobo/codegen"
      Dir.mkdir_p(cache)
      File.open(cache / "build.lock", "a", perm: 0o600) do |lock|
        lock.flock_exclusive
        return if current?
        Runcobo::Tasks.atomic_write(cache / "shard.yml", MANIFEST)
        Runcobo::Tasks.atomic_write(cache / "shard.lock", LOCK)
        @runner.run("shards", ["install", "--production"], chdir: cache)
        Dir.mkdir_p(binary.parent)
        temporary = File.tempfile(".crsql.", dir: binary.parent.to_s)
        temporary.close
        begin
          @runner.run("crystal", ["build", (cache / "lib/crsql/src/cli.cr").to_s, "-o", temporary.path], chdir: cache)
          File.chmod(temporary.path, 0o755)
          File.rename(temporary.path, binary)
          Runcobo::Tasks.atomic_write(stamp, TOOLCHAIN)
        ensure
          File.delete(temporary.path) if File.exists?(temporary.path)
        end
      end
    end

    def run(arguments : Array(String))
      build
      @runner.run(binary.to_s, arguments, chdir: @settings.root)
    end

    def generate
      run(["generate", "-f", @settings.generator_config])
    end

    def generate(destination : Path)
      build
      inputs = [@settings.generator_config] + @settings.generator_inputs
      inputs.each do |relative|
        source = @settings.root / relative
        target = destination / relative
        Dir.mkdir_p(target.parent)
        if Dir.exists?(source)
          FileUtils.cp_r(source, target)
        else
          FileUtils.cp(source, target)
        end
      end
      Dir.mkdir_p(destination / @settings.generated_directory)
      @runner.run(binary.to_s,
        ["generate", "-f", (destination / @settings.generator_config).to_s], chdir: destination)
    end

    def check
      Runcobo::Tasks.temporary_directory("generated-check-") do |destination|
        generate(destination)
        paths = Set(Path).new
        {@settings.root, destination}.each do |root|
          Dir.glob((root / @settings.generated_directory / "**/*").to_s).each do |file|
            paths << Path[file].relative_to(root) if File.file?(file)
          end
        end
        changed = paths.to_a.sort.select do |path|
          expected = destination / path
          actual = @settings.root / path
          !File.file?(expected) || !File.file?(actual) || File.read(expected) != File.read(actual)
        end
        unless changed.empty?
          raise ArgumentError.new("Generated content differed: #{changed.join(", ")}; run runcobo generate to update it")
        end
      end
      @output.puts "Generated queries are reproducible; source and generated files were not rewritten."
    end
  end
end
