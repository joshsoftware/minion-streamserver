require "./spec_helper"
require "../src/minion/streamserver/config/env_converter"
require "yaml"

class MockConfig
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  @[YAML::Field(key: "noenv")]
  property noenv : String

  @[YAML::Field(key: "withenv", converter: String::EnvConverter)]
  property withenv : String
end

ConfigYAML = <<-EYAML
---
noenv: I am static.
withenv: ENV["MOCKVAL"]
EYAML

describe String::EnvConverter do
  it "gets a static value" do
    ENV["MOCKVAL"] = "I am dynamic, from an environment variable."
    config = MockConfig.from_yaml(ConfigYAML)

    config.noenv.should eq "I am static."
    config.withenv.should eq "I am dynamic, from an environment variable."
  end
end
