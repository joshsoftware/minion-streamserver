require "./destination"

module Analogger
  class DestinationRegistry
    @@name_to_class_map = {} of String => Analogger::Destination.class

    def self.register(name, klass)
      @@name_to_class_map[name[/Analogger::Destination::(.*)/, 1].downcase] = klass
    end

    def self.registry
      @name_to_class_map
    end

    def self.get(key)
      @@name_to_class_map[key]
    end
  end
end
