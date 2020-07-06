module Minion
  class StreamServer
    class Core
      # This struct stores the configuration information for a given group.
      struct Command
        getter listener
        getter processor
        getter destination
        getter source
        getter channel

        def initialize(
          @listener : Minion::StreamServer::Command::Listener?,
          @processor : Minion::StreamServer::Command::Processor?,
          @destination : String?,
          @source : String?,
          @channel : String?
        )
        end

        def to_s
          <<-ETXT
          listener: #{@listener}
          processor: #{@processor}
          destination: #{@destination}
          source: #{@source}
          channel: #{@channel}
          ETXT
        end

        def ==(other)
          @listener == other.listener &&
            @processor == other.processor &&
            @destination == other.destination &&
            @source == other.source &&
            @channel == other.channel
        end
      end
    end
  end
end
