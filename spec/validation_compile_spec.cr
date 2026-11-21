require "./spec_helper"

private def compile_validation_fixture(name : String)
  diagnostics = IO::Memory.new
  status = Process.run("crystal", ["build", "--no-codegen", "--no-color", File.join(__DIR__, "fixtures", "validation", name)],
    output: diagnostics, error: diagnostics)
  {status, diagnostics.to_s}
end

describe "request contract declarations" do
  it "generates concrete required and optional output types" do
    status, diagnostics = compile_validation_fixture("correct_output_types.cr")
    status.success?.should be_true, diagnostics
  end

  {
    "removed_query_declaration.cr" => "NamedTuple parameter declarations were removed in Runcobo 3.0",
    "removed_url_declaration.cr"   => "NamedTuple parameter declarations were removed in Runcobo 3.0",
    "removed_form_declaration.cr"  => "NamedTuple parameter declarations were removed in Runcobo 3.0",
    "removed_json_declaration.cr"  => "NamedTuple parameter declarations were removed in Runcobo 3.0",
    "removed_params.cr"            => "undefined local variable or method 'params'",
    "removed_converters.cr"        => "undefined method 'from_http_param'",
    "duplicate_source.cr"          => "A request source can only have one contract",
    "inherited_duplicate.cr"       => "A request source can only have one contract",
    "both_body_sources.cr"         => "An action cannot declare both json and form contracts",
    "invalid_type.cr"              => "Expected a RequestValidation::Contract type",
    "invalid_option.cr"            => "unknown_keys must be :reject or :strip",
    "wrong_output_type.cr"         => "not Int64",
    "optional_output_type.cr"      => "not (String | Nil)",
    "multiple_input.cr"            => "Multiple request contracts",
    "inherited_multiple_input.cr"  => "Multiple request contracts",
  }.each do |fixture, message|
    it "rejects #{fixture}" do
      status, diagnostics = compile_validation_fixture(fixture)
      status.success?.should be_false
      diagnostics.should contain(message)
    end
  end
end
