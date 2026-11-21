require "./spec_helper"

describe "view configuration diagnostics" do
  it "rejects missing template" do
    output = IO::Memory.new
    result = Process.run("crystal", ["build", "--no-codegen", "--no-color", "spec/fixtures/render/missing_template.cr"], output: output, error: output)
    result.success?.should be_false
    output.to_s.should contain("Template not found: spec/fixtures/views/not_present.jbuilder")
  end

  it "rejects missing layout" do
    output = IO::Memory.new
    result = Process.run("crystal", ["build", "--no-codegen", "--no-color", "spec/fixtures/render/missing_layout.cr"], output: output, error: output)
    result.success?.should be_false
    output.to_s.should contain("Layout not found: spec/fixtures/layouts/not_present.jbuilder")
  end

  it "rejects unknown engine" do
    output = IO::Memory.new
    result = Process.run("crystal", ["build", "--no-codegen", "--no-color", "spec/fixtures/render/unknown_engine.cr"], output: output, error: output)
    result.success?.should be_false
    output.to_s.should contain("View engine must be :jbuilder or :water")
  end

  it "rejects dynamic template" do
    output = IO::Memory.new
    result = Process.run("crystal", ["build", "--no-codegen", "--no-color", "spec/fixtures/render/dynamic_template.cr"], output: output, error: output)
    result.success?.should be_false
    output.to_s.should contain("Template names must be string or symbol literals")
  end

  it "rejects repeated config" do
    output = IO::Memory.new
    result = Process.run("crystal", ["build", "--no-codegen", "--no-color", "spec/fixtures/render/repeated_config.cr"], output: output, error: output)
    result.success?.should be_false
    output.to_s.should contain("Runcobo.views may only be configured once")
  end

  it "selects Water as the configured default engine" do
    output = IO::Memory.new
    result = Process.run("crystal", ["run", "--no-color", "spec/fixtures/render/water_default.cr"], output: output, error: output)
    result.success?.should be_true, output.to_s
    output.to_s.should eq("text/html\n<span>default water</span>\n")
  end
end
