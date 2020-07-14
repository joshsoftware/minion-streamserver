module Minion
  class StreamServer
    class Destination
      class Io < Minion::StreamServer::Destination
        getter handle : Fiber
        getter channel
        getter io : IO

        NEWLINE = "\n".to_slice

        def initialize(destination : String, @options : Array(String)|Array(Hash(String,Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil)))
          @channel = Channel(Frame).new(1024)
          @io = case destination
                when /stdout/i
                  STDOUT
                when /stderr/i
                  STDERR
                else
                  raise "Unknown IO: #{destination}"
                end
          @handle = spawn do
            begin
              loop do
                frame = @channel.receive
                @io.write "#{frame.uuid.to_s}\t#{frame.data[1..-1].join("\t")}".to_slice
                @io.write NEWLINE unless frame.data.last[-1] == '\n'
              end
            rescue e : Exception
              STDERR.puts e
              STDERR.puts e.backtrace.join("\n")
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
