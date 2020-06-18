module Minion
  class StreamServer
    class Config
      @[YAML::Serializable::Options(emit_nulls: true)]
      struct Response
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        @[YAML::Field(key: "destination")]
        property destination : String

        @[YAML::Field(key: "type")]
        property type : String = "file"

        @[YAML::Field(key: "options")]
        property options : Array(String) = ["ab"]
      end
    end
  end
end
