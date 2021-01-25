module Minion
  class StreamServer
    class Core
      # This struct stores the configuration information for a given group.
      struct Telemetry
        getter type
        getter options
        getter destination : Minion::StreamServer::Destination | Nil

        DEFAULT_TYPE    = "file"
        DEFAULT_OPTIONS = ["ab"]

        def initialize(
          @type : String = DEFAULT_TYPE,
          @options : Array(String) | Array(ConfigDataHash) = DEFAULT_OPTIONS,
          @destination = Minion::StreamServer::Core.default_log_destination
        )
        end

        def to_s
          "type: #{type}\noptions: #{@options.inspect}"
        end

        def ==(other)
          @type == other.type &&
            @options == other.options
        end
      end
    end
  end
end
