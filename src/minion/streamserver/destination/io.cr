module Minion
  class StreamServer
    class Destination
      class Io < Minion::StreamServer::Destination
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
        getter io : IO

        def initialize(@group : Group, io_name : String, @options : Array(String))
          @channel = Channel(Frame).new
          @io = case io_name
          when /stdout/i
            STDOUT
          when /stderr/i
            STDERR
          else
            raise "Unknown IO: #{io_name}"
          end

          @handle = spawn do
            while frame = @channel.receive?
              @io.write frame.data[2].to_slice
            end
          end
        end

        def reopen
          stream = @io
          @io.flush
          @io.reopen(stream)
        end

        def flush
          @io.flush unless @io.closed?
        end
      end
    end
  end
end