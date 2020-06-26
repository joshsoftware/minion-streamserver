module Minion
  class StreamServer
    class Config
      @[YAML::Serializable::Options(emit_nulls: true)]
      struct Telemetry
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        @[YAML::Field(key: "destination", emit_null: true, default: "STDERR")]
        property destination : String?

        @[YAML::Field(key: "type", default: nil)]
        property type : String?

        @[YAML::Field(key: "options", default: ["ab"])]
        property options : Array(String) = [] of String

        @[YAML::Field(key: "label", emit_null: true, default: "telemetry")]
        property label : String? = "telemetry"
      end
    end
  end
end
