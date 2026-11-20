require "../../../src/runcobo"

class CompileContract < RequestValidation::Contract
  schema do
    required :id, Int64
    optional :nickname, String
  end
end
