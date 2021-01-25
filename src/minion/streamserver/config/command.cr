module Minion
  class StreamServer
    # module String::EnvConverter
    #   def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
    #     unless node.is_a?(YAML::Nodes::Scalar)
    #       node.raise "Expected scalar, not #{node.class}"
    #     end
    #     nv = node.value.gsub(/ENV\["(\w*)"\]/) { ENV.has_key?($1) ? ENV[$1] : "" }
    #   end
    # end

    class Config
      @[YAML::Serializable::Options(emit_nulls: true)]
      struct Command
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        @[YAML::Field(key: "listener")]
        property listener : String = "postgresql"

        @[YAML::Field(key: "destination", converter: String::EnvConverter, emit_null: true)]
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
