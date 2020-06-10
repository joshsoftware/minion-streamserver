require "yaml"
require "option_parser"
require "./config"

module Analogger
  class CommandLine
    property config : Config

    def initialize
      @config = parse_options
    end

    def parse_options
      empty_config = <<-EYAML
      ---
      logs: []
      EYAML
      config = Config.from_yaml(empty_config)
      # Config file to read
      #
      # port: 12345
      # secret: abcdef
      # interval: 1
      # default_log: /var/log/emlogger
      # logs:
      # - service: client1
      #   levels: info
      #   logfile: /foo/bar.txt
      #   cull: true
      #
      OptionParser.new do |opts|
        opts.banner = "Analogger v#{Analogger::VERSION}\nUsage: analogger.rb [options]"
        opts.separator ""
        opts.on("-c", "--config CONFFILE", "The configuration file to read.") do |conf|
          config = Config.from_yaml(File.read(conf))
        end
        opts.on("-p", "--port [PORT]", "The port to receive connections on.") do |port|
          config.port = port
        end
        opts.on("-h", "--host [HOST]", "The host to bind the connection to.") do |host|
          config.host = host
        end
        opts.on("-r", "--secret [KEY]", "The secret key that authenticates a control session.") do |secret|
          config.secret = secret
        end
        opts.on("-k", "--key [KEY]", "The secret key that authenticates a valid client session.") do |secret|
          config.key = secret
        end
        opts.on("-i", "--interval [INTERVAL]", "The interval between queue writes.  Defaults to 1 second.") do |interval|
          config.interval = interval
        end
        opts.on("-s", "--syncinterval [INTERVAL]", "The interval between queue syncs.  Defaults to 60 seconds.") do |interval|
          config.syncinterval = interval
        end
        opts.on("-d", "--default [PATH]", "The default log destination.  Defaults to stdout.") do |default|
          config.default_log = default
        end
        opts.on("-x", "--daemonize", "Tell the Analogger to daemonize itself.") do
          config.daemonize = true
        end
        opts.on("-w", "--writepid [FILENAME]", "The filename to write a PID file to.") do |pidfile|
          config.pidfile = pidfile || "analogger.pid"
        end
        opts.on("--help", "Show this help") do
          puts opts
          exit
        end
        opts.on("-v", "--version", "Show the current version of Analogger.") do
          puts "Analogger v#{Analogger::VERSION}"
          exit
        end
        opts.invalid_option do |flag|
          STDERR.puts "Error: #{flag} is not a valid option."
          STDERR.puts opts
          exit(1)
        end
      end.parse

      puts
      config
    end
  end
end
