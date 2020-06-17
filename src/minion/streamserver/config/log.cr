module Minion
  class StreamServer
    class Config
      @[YAML::Serializable::Options(emit_nulls: true)]
      struct Log
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        # service
        # logfile
        # cull
        # type
        # options
        @[YAML::Field(key: "service")]
        property service : String | Array(String) = "default"

        @[YAML::Field(key: "destination")]
        property destination : String

        @[YAML::Field(key: "cull")]
        property cull : Bool = true

        @[YAML::Field(key: "type")]
        property type : String = "file"

        @[YAML::Field(key: "options")]
        property options : Array(String) = ["ab"]

        @[YAML::Field(key: "default")]
        property default : Bool = false
      end
    end
  end
end
