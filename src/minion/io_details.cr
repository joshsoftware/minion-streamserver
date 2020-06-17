module Minion
  class IoDetails
    property read_message_size
    property size_read
    property send_size_buffer
    property read_message_body
    property read_message_size
    property message_size
    property data_buffer
    property receive_size_buffer

    def initialize(
      @size_read = 0,
      @send_size_buffer = Slice(UInt8).new(2),
      @read_message_body = false,
      @read_message_size = true,
      @message_size = 0,
      @data_buffer = Slice(UInt8).new(Client::MAX_MESSAGE_LENGTH),
      @receive_size_buffer = Slice(UInt8).new(2)
    )
      super
    end
  end
end
