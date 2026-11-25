require "./database"

module Runcobo::Tasks
  class Server
    def initialize(@database : Database)
    end

    def environment(inherited = ENV.to_h) : Hash(String, String)
      settings = @database.settings
      environment = inherited.dup
      if key = settings.secret_environment
        Dir.mkdir_p(@database.local)
        secret = @database.local / "development-secret"
        unless File.exists?(secret)
          temporary = File.tempfile(".development-secret.", ".tmp", dir: @database.local.to_s)
          begin
            temporary.print(Random::Secure.urlsafe_base64(48))
            temporary.close
            File.link(temporary.path, secret)
          rescue File::AlreadyExistsError
            # Another startup created the same local secret.
          ensure
            temporary.close unless temporary.closed?
            File.delete(temporary.path) if File.exists?(temporary.path)
          end
        end
        environment[key] = File.read(secret).strip
      end
      environment["DATABASE_URL"] = @database.database_url("development")
      settings.development_environment.each { |key, value| environment[key] ||= value }
      if key = settings.public_base_environment
        environment[key] ||= "http://#{environment["HOST"]}:#{environment["PORT"]}"
      end
      environment
    end

    def run
      @database.prepare("development")
      settings = @database.settings
      env = environment
      seed = settings.seed_command
      @database.runner.run(seed.first, seed[1..], env: env, chdir: settings.root) unless seed.empty?
      server = settings.server_command
      Process.exec(server.first, server[1..], env: env, clear_env: true, chdir: settings.root)
    end
  end
end
