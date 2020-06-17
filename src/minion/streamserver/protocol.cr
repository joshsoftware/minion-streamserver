require "msgpack"
require "../frame"

module Minion
  class StreamServer
    class Protocol
      MAX_MESSAGE_LENGTH = 8192
      REGEXP_COLON       = /:/

      @length : Int32?
      @message_buffer : Slice(UInt8)

      def initialize(@client : TCPSocket, @logger : Minion::StreamServer::Core)
        @length = nil
        @pos = 0
        @authenticated = false # Actual working authentication is still a TODO item.
        @send_size_buffer = Slice(UInt8).new(2)
        @receive_size_buffer = Slice(UInt8).new(2)
        @size_read = 0
        @message_bytes_read = 0
        @message_size = 0_u16
        @data_buffer = Slice(UInt8).new(MAX_MESSAGE_LENGTH)
        @message_buffer = @data_buffer[0, 1]
        @read_message_size = true
        @read_message_body = false
      end

      def receive
        until @client.closed?
          if @read_message_size
            if @size_read == 0
              @size_read = @client.read(@send_size_buffer)
              if @size_read < 2
                Fiber.yield
              end
            elsif @size_read == 1
              byte = @client.read_byte
              if byte
                @send_size_buffer[1] = byte
                @size_read = 2
              end
            end

            if @size_read > 1
              @read_message_body = true
              @read_message_size = false
              @size_read = 0
            end
          end

          if @read_message_body
            if @message_size == 0
              @message_size = IO::ByteFormat::BigEndian.decode(UInt16, @send_size_buffer)
              @message_buffer = @data_buffer[0, @message_size]
            end

            if @message_bytes_read < @message_size
              # Try to read the rest of the bytes.
              remaining_bytes = @message_size - @message_bytes_read
              read_buffer = @message_buffer[@message_bytes_read, remaining_bytes]
              bytes_read = @client.read(read_buffer)
              @message_bytes_read += bytes_read
            end

            if @message_bytes_read >= @message_size
              msg = Tuple(String, String, Array(String)).from_msgpack(@message_buffer).as(Tuple(String, String, Array(String)))
              handle msg
              @read_message_body = false
              @read_message_size = true
              @message_size = 0
              @message_bytes_read = 0
            else
              Fiber.yield
            end
          end
        end
      end

      def send_data(data, flush_after_send = false)
        msg = data.to_msgpack
        IO::ByteFormat::BigEndian.encode(msg.size.to_u16, @send_size_buffer)
        @client.write(@send_size_buffer)
        @client.write(data.to_msgpack)
        @client.flush if flush_after_send
      end

      # The handler receives a frame, and then dispatches it according to the command variety.
      def handle(msg)
        frame = Frame.new(*msg)

        @logger.handle_frame(frame, self)
      end
    end
  end
end
