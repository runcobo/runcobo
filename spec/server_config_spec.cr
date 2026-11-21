require "./spec_helper"

describe "server environment configuration" do
  it "decodes reuse_port as a boolean rather than string presence" do
    Runcobo.reuse_port_from_env(nil).should be_false
    Runcobo.reuse_port_from_env("false").should be_false
    Runcobo.reuse_port_from_env("true").should be_true
    expect_raises(ArgumentError, "REUSE_PORT must be true or false") { Runcobo.reuse_port_from_env("no") }
  end
end
