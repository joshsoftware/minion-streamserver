module Analogger
  class Destination
    class File < Analogger::Destination
      def initialize(@file_handle : ::File)
      end

      def self.open(logfile, options : Array(String) | Nil) : File
        mode = options.as?(Array) ? options.first : "ab"
        file_handle = ::File.open(logfile, mode)
        self.new(file_handle)
      end

      forward_missing_to(@file_handle)
    end
  end
end
