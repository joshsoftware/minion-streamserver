require "./processor"

module Minion
  class StreamServer
    class Command
      class ProcessorRegistry
        @@name_to_class_map = {} of String => Minion::StreamServer::Command::Processor.class

        def self.register(name, klass)
          @@name_to_class_map[name[/Minion::StreamServer::Command::Processor::(.*)/, 1].downcase] = klass
        end

        def self.registry
          @name_to_class_map
        end

        def self.get(key)
          @@name_to_class_map[key]
        end
      end
    end
  end
end

require "./processor/*"
