module Minion
  class StreamServer
    class Core
      def self.setup_destination(destination : Minion::StreamServer::Destination) : Minion::StreamServer::Destination
        destination.reopen if destination.respond_to? :reopen
        destination
      end

      def self.setup_destination(
        destination : String, type : String? = "file",
        options : Array(String) | Array(ConfigDataHash)? = ["ab"],
        failure_notification_channel = Channel(Bool).new
      ) : Minion::StreamServer::Destination
        type ||= "file"
        type = type.to_s.downcase

        obj = Minion::StreamServer::DestinationRegistry.get(type)
        obj.new(destination, options, failure_notification_channel)
      rescue e : Exception
        STDERR.puts e
        STDERR.puts e.backtrace.join("\n")
        raise e
      end

      def setup_processor(
        type : String,
        agent_registry : Hash(String, Protocol),
        destination : String?
      )
        type = type.to_s.downcase

        obj = Minion::StreamServer::Command::ProcessorRegistry.get(type)
        obj.new(
          destination: destination,
          agent_registry: agent_registry
        )
      rescue ex
        STDERR.puts ex
        STDERR.puts ex.backtrace.join("\n")
        raise ex
      end

      def setup_listener(
        type : String,
        channel : String,
        destination : String?,
        processor : Minion::StreamServer::Command::Processor
      )
        type = type.to_s.downcase

        obj = Minion::StreamServer::Command::ListenerRegistry.get(type)
        obj.new(
          destination: destination,
          channel: channel,
          processor: processor
        )
      end

      ##########
      def set_config_defaults
        @config.host ||= "127.0.0.1"

        # @config.interval = @config.interval.nil? ? 1 : @config.interval.to_i
        @config.syncinterval = @config.syncinterval.nil? ? 60 : @config.syncinterval.to_i
        if !@config.default_log.to_s.blank?
          Minion::StreamServer::Core.default_log = @config.default_log.to_s
        end
      end

      ##########
      def setup_signal_traps
        safe_trap(signal_list: EXIT_SIGNALS) { handle_pending_and_exit }
        safe_trap(signal_list: RELOAD_SIGNALS) {
          # TODO: make HUP work again; cleanup_and_reopen
        }
        safe_trap(signal_list: RESTART_SIGNALS) do
          purge_queues
          Process.exec(
            command: invocation_arguments.command,
            args: invocation_arguments.args
          )
        end
      end

      def safe_trap(signal_list : Array(Signal), &operation)
        signal_list.each do |sig|
          sig.trap { operation.call }
        end
      end
    end
  end
end
