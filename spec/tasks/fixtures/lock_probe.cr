require "../../../src/tasks/database"
root, ready, acquired = ARGV
settings = Runcobo::Tasks::Config.new(Path[root], "sample", "sample", "tester", 55439)
database = Runcobo::Tasks::Database.new(settings)
File.write(ready, "ready")
database.migration_lock("postgresql://localhost:55439/sample_test") do
  File.write(acquired, "acquired")
end
