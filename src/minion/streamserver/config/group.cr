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

        @[YAML::Field(key: "logs")]
        property logs : Array(Minion::StreamServer::Config::Log)

        @[YAML::Field(key: "telemetry")]
        property telemetry : Array(Minion::StreamServer::Config::Telemetry)

        @[YAML::Field(key: "responses")]
        property responses : Array(Minion::StreamServer::Config::Response)
      end
    end
  end
end
