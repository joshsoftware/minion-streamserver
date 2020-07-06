module Minion
  class StreamServer
    class Config
      @[YAML::Serializable::Options(emit_nulls: true)]
      struct Command
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        @[YAML::Field(key: "listener")]
        property listener : String = "postgresql"

        @[YAML::Field(key: "destination", emit_null: true)]
        property destination : String?

        @[YAML::Field(key: "channel")]
        property channel : String

        @[YAML::Field(key: "source", emit_null: true)]
        property source : String = "command_queues"

        @[YAML::Field(key: "processor")]
        property processor : String = "postgresql"
      end
    end
  end
end
