lib LibC
  fun setsid : PidT
  fun getsid(pid : PidT) : PidT
end

# TODO: This should be deprecated; daemonizing should be farmed out to the OS.
module Analogger
  class Core
    def setsid
      LibC.setsid
    end

    def sid(pid : Int32 = 0)
      LibC.getsid(pid)
    end

    def daemonize # TODO: Is there a better alternative with Crystal?
      if (child_pid = fork)
        puts "PID #{child_pid.pid}" unless @config.pidfile
        exit
      end
      setsid

      exit if fork
    rescue Exception
      puts "This Crystal(#{Crystal::DESCRIPTION}) does not appear to support fork/setsid; skipping"
    end
  end
end
