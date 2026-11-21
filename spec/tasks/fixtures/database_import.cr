require "../../../src/tasks/database"
settings = Runcobo::Tasks::Config.new(Path[Dir.current], "sample", "sample", "sample", 55439)
Runcobo::Tasks::Database.new(settings).migrate("test") if ARGV.includes?("--execute")
