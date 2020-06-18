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

        getter handle : Fiber
        getter channel
        getter file_handle : ::File

        NEWLINE = "\n".to_slice

        def initialize(@destination : String, @options : Array(String))
          @channel = Channel(Frame).new(1024)
          mode = @options.as?(Array) ? options.first : "ab"
          @file_handle = ::File.open(@destination, mode)
          @handle = spawn do
            begin
            while frame = @channel.receive
              @file_handle.write "#{frame.uuid.to_s}\t#{frame.data[1..-1].join("\t")}".to_slice
              @file_handle.write NEWLINE unless frame.data[2][-1] == '\n'
            end
          rescue e : Exception
            STDERR.puts e
            STDERR.puts e.backtrace.join("\n")
            end
          end
        end

        def reopen
          mode = @options.as?(Array) ? options.first : "ab"
          @file_handle.flush
          @file_handle = @file_handle.reopen(@destination, mode)
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
