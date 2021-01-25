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
        getter options : Array(String) | Array(ConfigDataHash)
        getter default : Bool
        getter failure_notification_channel : Channel(Bool)

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
          # This shouldn't be nillable. The compiler insists that it is. So,
          # let's use not_nil! and see if anything throws an error that can
          # shed some light on where the nil could be coming from, because right
          # now I am not seeing it.
          @failure_notification_channel = @destination.not_nil!.failure_notification_channel
          @raw_destination = @raw_destination.to_s
          @cull = !!cull
        end

        def valid
          @destination.valid
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
