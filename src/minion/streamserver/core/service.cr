module Minion
  class StreamServer
    class Core
      # This struct stores the configuration information for a given logging destination.
      struct Service
        getter service : String
        getter raw_destination : String?
        getter destination : Minion::StreamServer::Destination?
        getter cull : Bool?
        getter type : String?
        getter options : Array(String) | Array(Hash(String, Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil))
        getter default : Bool

        DEFAULT_SERVICE = "default"
        DEFAULT_TYPE    = "file"
        DEFAULT_OPTIONS = ["ab"]

        def initialize(
          @service = DEFAULT_SERVICE,
          @raw_destination = Minion::StreamServer::Core.default_log,
          @destination = Minion::StreamServer::Core.default_log_destination,
          @cull = true,
          @type = DEFAULT_TYPE,
          @options = DEFAULT_OPTIONS,
          @default = false
        )
          @raw_destination = @raw_destination.to_s
          @cull = !!cull
        end

        def to_s
          "service: #{@service}\nraw_destination: #{@raw_destination}\ndestination: #{@destination}\ncull: #{@cull}\ntype: #{@type}\noptions: #{@options.inspect}"
        end

        def ==(other)
          other.service == @service &&
            other.raw_destination == @raw_destination &&
            other.cull == @cull &&
            other.type == @type &&
            other.options == @options &&
            other.default == @default
        end
      end
    end
  end
end
