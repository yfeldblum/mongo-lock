class Clock

  attr_accessor :now

  def initialize(now)
    self.now = now
  end

  def travel(d, &b)
    b ? travel_block(d, &b) : travel_noblock(d)
  end

  private

  def travel_noblock(d)
    self.now += d
  end

  def travel_block(d)
    orig = now
    self.now = orig + d
    yield
  ensure
    self.now = orig
  end

end
