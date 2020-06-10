module Analogger
  class Core
    class ExecArguments
      property command : String
      property args : Array(String)

      def initialize(command, args)
        @command = command
        @args = args
      end
    end
  end
end
