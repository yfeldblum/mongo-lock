class PipeQueue

  def initialize
    self.r, self.w = IO.pipe
    prepare
  end

  def enqueue(s)
    w.puts s
  end

  def eof!
    w.close unless w.closed?
  end

  def dequeue
    r.gets.strip
  end

  def eof?
    r.eof?
  end

  def done!
    r.close unless r.closed?
  end

  private

  attr_accessor :r, :w

  def prepare
    r.sync = true
    w.sync = true
  end

end
