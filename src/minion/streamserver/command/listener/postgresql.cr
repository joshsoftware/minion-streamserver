require "pg"

module Minion
  class StreamServer
    class Command
      class Listener
        class Postgresql < Minion::StreamServer::Command::Listener
          property listener : PG::ListenConnection?

          def initialize(destination, channel, processor)
            unless destination.nil?
              @listener = PG.connect_listen(destination, channel) do
                spawn(name: "Command Queue Listener") do
                  processor.call
                end
              end
            end
          end
        end
      end
    end
  end
end
