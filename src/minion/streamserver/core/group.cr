module Minion
  class StreamServer
    class Core
      # This struct stores the configuration information for a given group.
      struct Group
        getter id
        getter key
        getter logs
        getter telemetry
        getter command
        getter default_log
        property valid
        getter failure_notification_channel : Channel(Bool)

        def initialize(
          @id : String,
          @key : String,
          @logs : Hash(String, Service) = Hash(String, Service).new { |h, k| h[k] = Service.new(service: k) },
          @default_log : Minion::StreamServer::Core::Service | String = "",
          @telemetry : Array(Telemetry) = [] of Telemetry,
          @command : Array(Command)? = [] of Command,
          @valid : Bool = true,
          @failure_notification_channel = Channel(Bool).new
        )
        end

        def to_s
          log_map = logs.map { |l| "    #{l}" }.join("\n")
          "id: #{@id}\nkey: #{@key}\nlogs:\n#{log_map}"
        end

        def ==(other)
          @id == other.id &&
            @key == other.key
        end

        def authenticated?(id, key)
          @id == id &&
            @key == key
        end
      end
    end
  end
end
