module Minion
  class StreamServer
    class Destination
      class File < Minion::StreamServer::Destination
        # def initialize(@file_handle : ::File)
        # end
        #
        # def self.open(logfile, options : Array(String) | Nil) : File
        #   mode = options.as?(Array) ? options.first : "ab"
        #   file_handle = ::File.open(logfile, mode)
        #   self.new(file_handle)
        # end
        #
        # forward_missing_to(@file_handle)

        getter handle
        getter channel
        getter file_handle : ::File

        def initialize(@group : Group, @filename : String, @options : Array(String))
          @channel = Channel(Frame).new
          mode = @options.as?(Array) ? options.first : "ab"
          @file_handle = ::File.open(@filename, mode)
          @handle = spawn do
            while frame = @channel.receive?
              @file_handle.write frame.data[2].to_slice
            end
          end
        end

        def reopen
          mode = @options.as?(Array) ? options.first : "ab"
          @file_handle.flush
          @file_handle = @file_handle.reopen(@filename, mode)
        end

        def flush
          unless @file_handle.closed?
            @file_handle.flush
            @file_handle.fsync
          end
        end
      end
    end
  end
end
