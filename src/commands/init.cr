require "./init_template"

module Runcobo
  module Commands::Init
    def self.run(path, project_name)
      Runcobo::InitTemplate.new(project_name).render("#{path}/#{project_name}")
    end
  end
end
