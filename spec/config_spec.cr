require "./spec_helper"
require "../src/minion/streamserver/config"
require "yaml"

describe Minion::StreamServer::Config do

  it "reads the sample configuration" do
    config = Minion::StreamServer::Config.from_yaml(File.read("sample.cnf"))

    config.port.should eq "47990"
    config.service_defaults.not_nil!.service.should eq "stderr"
    config.command.not_nil![0].listener.should eq "postgresql"
    config.groups.not_nil![0].id.should eq "kirks-minion-stuff"
  end
end