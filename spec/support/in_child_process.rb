module InChildProcess

  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def in_child_process_jruby_pending
      defined?(JRuby) or return
      before { pending "jruby has no fork" }
    end
  end

  def in_child_process
    block_given? or raise ArgumentError, "block not given"
    r, w = IO.pipe
    r.sync = true
    w.sync = true
    pid = Process.fork do
      r.close
      begin
        w.write Marshal.dump(ok: yield)
      rescue => e
        w.write Marshal.dump(err: e)
      end
    end
    w.close
    v = Marshal.load(r.read)
    v[:err] ? raise(v[:err]) : v[:ok]
  ensure
    r.close if r
    Process.waitpid2(pid) if pid
  end

end
