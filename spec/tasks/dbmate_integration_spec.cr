require "./spec_helper"

if integration_url = ENV["RUNCOBO_DBMATE_INTEGRATION_URL"]?
  describe "cobo dbmate integration" do
    it "compares real schema dumps and rejects a rollback that leaves a different collation" do
      Runcobo::Tasks.temporary_directory("dbmate-verify-") do |root|
        path = TaskSpec.migration(root)
        File.write(path, "CREATE TABLE sample (name text COLLATE \"default\");\n")
        change = path.parent / "20261121082720_change_collation.sql"
        up = %(ALTER TABLE sample ALTER COLUMN name TYPE text COLLATE "C";)
        down = %(ALTER TABLE sample ALTER COLUMN name TYPE text COLLATE "default";)
        config = <<-YAML
          name: sample
          database_prefix: runcobo_tasks
          database_user: unused
          database_port: 65432
          YAML
        File.write(root / "runcobo.yml", config)
        settings = Runcobo::Tasks::Config.load(root)
        database = Runcobo::Tasks::Database.new(settings)
        env = database.connection_environment.merge({"TEST_DATABASE_URL" => integration_url})
        executable = (TaskSpec::ROOT / "bin/cobo").to_s

        File.write(change, "-- migrate:up\n#{up}\n-- migrate:down\nSELECT 1;\n")
        status = database.runner.run(executable, ["db", "status", "test"], env: env, chdir: root, capture: true)
        status.output.should contain("[ ] 20261120082720")
        status.output.should contain("[ ] 20261121082720")
        uri = URI.parse(integration_url)
        params = HTTP::Params.parse(uri.query || "")
        params["sslmode"] = "disable" unless params.has_key?("sslmode")
        uri.query = params.to_s
        deployment_env = env.merge({"PRODUCTION_DATABASE_URL" => uri.to_s})
        deployment_status = database.runner.run(executable, ["db", "status", "production", "--quiet"],
          env: deployment_env, chdir: root, capture: true, check: false)
        deployment_status.exit_code.should eq(1)
        deployment_status.output.should be_empty
        deployment_status.error.should be_empty
        database.runner.run(executable, ["db", "wait", "production", "--wait-timeout", "5s"],
          env: deployment_env, chdir: root, capture: true)
        console = database.runner.run(executable, ["db", "console", "test"], env: env, chdir: root,
          input: IO::Memory.new("SELECT current_database();\n"), capture: true)
        console.output.should contain("runcobo_tasks_test")
        failed = database.runner.run(executable, ["db", "verify"], env: env, chdir: root, capture: true, check: false)
        failed.exit_code.should eq(1)
        failed.error.should contain("Rollback 20261121082720: database schema differs")

        File.write(change, "-- migrate:up\n#{up}\n-- migrate:down\n#{down}\n")
        database.runner.run(executable, ["db", "verify"], env: env, chdir: root, capture: true)
          .output.should contain("Verified 2 migrations")
        database.runner.run(executable, ["db", "snapshot"], env: env, chdir: root, capture: true)
        output = root / settings.snapshot_path
        source = File.read(output)
        source.should contain("CREATE TABLE public.sample")
        source.should contain(%(COLLATE pg_catalog."C"))
        source.should_not contain("schema_migrations")
        (File.info(output).permissions.value & 0o222).should eq(0)

        url = database.database_url("test", env)
        result = database.psql(url, "SELECT count(*) FROM pg_namespace WHERE nspname LIKE 'cobo_verify_%'")
        result.output.strip.should eq("0")
      end
    end
  end
end
