module Minion
  class StreamServer
    class Destination
      class Io < Minion::StreamServer::Destination
        getter handle : Fiber
        getter channel
        getter io : IO

        NEWLINE = "\n".to_slice

        def initialize(
          destination : String,
          @options : Array(String) | Array(ConfigDataHash),
          @failure_notification_channel : Channel(Bool),
          start_monitor_thread = true
        )
          @channel = Channel(Frame).new(1024)
          @io = case destination
                when /stdout/i
                  STDOUT
                when /stderr/i
                  STDERR
                else # Should this handle other destinations? What's the differnce between this and File?
                  raise "Unknown IO: #{destination}"
                end

          spawn monitor_io if start_monitor_thread

          @handle = spawn do
            begin
              loop do
                frame = @channel.receive
                @io.write "#{frame.uuid.to_s}\t#{frame.data[1..-1].join("\t")}".to_slice
                @io.write NEWLINE unless frame.data.last[-1] == '\n'
              end
            rescue e : Exception
              notify_upstream_of_destination_failure
              STDERR.puts e
              STDERR.puts e.backtrace.join("\n")
            end
          end
        end

        def monitor_io
          loop do # Write nils to the IO. If they succeed, yay. If they fail, something is wrong.
            begin
              if !io.closed?
                notify_upstream_of_destination_success
              else
                notify_upstream_of_destination_failure
              end
            end
            sleep 5
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
