module Minion
  class StreamServer
    alias GenericData = Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil
    alias ConfigDataHash = Hash(String, GenericData)
  end
end
