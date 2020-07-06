module Minion
  class StreamServer
    class Config
      @[YAML::Serializable::Options(emit_nulls: true)]
      struct Group
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        # service
        # logfile
        # cull
        # type
        # options
        @[YAML::Field(key: "id")]
        property id : String

        @[YAML::Field(key: "key")]
        property key : String = ""

        @[YAML::Field(
          key: "service_defaults",
          default: {
            "service"     => nil,
            "destination" => nil,
            "cull"        => true,
            "type"        => nil,
            "options"     => nil,
          })]
        property service_defaults : Minion::StreamServer::Config::Service?

        @[YAML::Field(key: "services")]
        property services : Array(Minion::StreamServer::Config::Service)

        @[YAML::Field(key: "telemetry")]
        property telemetry : Array(Minion::StreamServer::Config::Telemetry)

        @[YAML::Field(key: "command", emit_nulls: true)]
        property command : Array(Minion::StreamServer::Config::Command)?
      end
    end
  end
end
