require "./app"

CrSQLExample::Store.open(ENV["DATABASE_URL"]) do |store|
  Runcobo.start(handlers: CrSQLExample.handlers(store))
end
