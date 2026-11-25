require "path"
require "yaml"

module Runcobo::Tasks
  class ProjectTask
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter command : Array(String)
    getter description : String = ""
  end

  # Development configuration is separate from application runtime configuration.
  class Config
    include YAML::Serializable
    include YAML::Serializable::Strict

    @[YAML::Field(ignore: true)]
    property root : Path = Path[Dir.current]
    getter name : String
    getter database_prefix : String
    getter database_user : String
    getter database_port : Int32
    getter migration_directory : String = "db/migrations"
    getter rollback_directory : String = "db/rollbacks"
    getter generator_config : String = "sqlc.yaml"
    getter generator_inputs : Array(String) = ["db/migrations", "db/queries"]
    getter generator_binary : String = "bin/crsql"
    getter generated_directory : String = "src/persistence/generated"
    getter snapshot_path : String = "db/schema.snapshot.sql"
    getter secret_environment : String? = nil
    getter seed_command : Array(String) = [] of String
    getter server_command : Array(String) = ["crystal", "run", "src/main.cr"]
    getter development_environment : Hash(String, String) = {} of String => String
    getter public_base_environment : String? = nil
    getter application_entry : String? = nil
    getter tasks : Hash(String, ProjectTask) = {} of String => ProjectTask

    def initialize(@root : Path,
                   @name : String,
                   @database_prefix : String,
                   @database_user : String,
                   @database_port : Int32,
                   @migration_directory : String = "db/migrations",
                   @rollback_directory : String = "db/rollbacks",
                   @generator_config : String = "sqlc.yaml",
                   @generator_inputs : Array(String) = ["db/migrations", "db/queries"],
                   @generator_binary : String = "bin/crsql",
                   @generated_directory : String = "src/persistence/generated",
                   @snapshot_path : String = "db/schema.snapshot.sql",
                   @secret_environment : String? = nil,
                   @seed_command : Array(String) = [] of String,
                   @server_command : Array(String) = ["crystal", "run", "src/main.cr"],
                   @development_environment : Hash(String, String) = {} of String => String,
                   @public_base_environment : String? = nil,
                   @application_entry : String? = nil,
                   @tasks : Hash(String, ProjectTask) = {} of String => ProjectTask)
    end

    def self.load(root : Path) : self
      config = from_yaml(File.read(root / "runcobo.yml"))
      config.root = root.expand
      config
    end
  end
end
