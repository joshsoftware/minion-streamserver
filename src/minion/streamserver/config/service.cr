module Minion
  class StreamServer
    class Config
      @[YAML::Serializable::Options(emit_nulls: true)]
      struct Service
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        # service
        # logfile
        # cull
        # type
        # options
        @[YAML::Field(key: "service", default: "default")]
        property service : String | Array(String) = "default"

        @[YAML::Field(key: "destination", emit_null: true, default: "STDERR")]
        property destination : String?

        @[YAML::Field(key: "cull")]
        property cull : Bool = true

        @[YAML::Field(key: "type", default: nil)]
        property type : String?

        @[YAML::Field(key: "options", default: ["ab"])]
        property options : Array(String) = ["ab"]

        @[YAML::Field(key: "default")]
        property default : Bool = false
      end
    end
  end
end
