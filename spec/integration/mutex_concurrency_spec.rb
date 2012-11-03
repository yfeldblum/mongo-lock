require "mongo/lock/mutex"
require "spec_helper"

describe Mongo::Lock::Mutex do
  include InChildProcess

  let(:collection) { db["mutexes"] }
  let(:key) { "/path-to/some-doc" }

  def rand(n)
    SecureRandom.random_number * n
  end

  def randw(n)
    rand(n).to_i + 1
  end

  def count_leading_edges(q)
    changes = 0
    last = nil
    until q.eof?
      n = q.dequeue
      next if last == n
      last = n
      changes += 1
    end
    changes
  end

  def count_leading_edges_from_many_threads(n)
    q = PipeQueue.new
    m = ::Mutex.new
    d = 0
    threads = n.times.map do |i|
      Thread.new do
        begin
          yield(q)
        ensure
          m.synchronize do
            d += 1
            q.eof! if d == n
          end
        end
      end
    end
    count_leading_edges(q)
  ensure
    threads.each(&:join)
    q.done! if q
  end

  def count_leading_edges_from_many_child_processes(n)
    q = PipeQueue.new
    pids = n.times.map do |i|
      Process.fork do
        q.done!
        begin
          yield(q)
        ensure
          q.eof!
        end
      end
    end
    q.eof!
    count_leading_edges(q)
  ensure
    pids.each{|pid| Process.waitpid2(pid)}
    q.eof! if q
    q.done! if q
  end

  def randomly_with_random_sleeps(c)
    randw(c).times do
      sleep rand(0.05)
      randw(c * 50).times do
        yield
      end
    end
  end

  def enqueue_tag_randomly_with_random_sleeps(c, q)
    tag = "#{Process.pid}-#{Thread.current.object_id}"
    randomly_with_random_sleeps(c) do
      q.enqueue(tag)
    end
  end

  let(:c) { 10 }

  context "with threads" do
    it "does not mutex without a mutex" do
      changes = count_leading_edges_from_many_threads(c) do |q|
        enqueue_tag_randomly_with_random_sleeps(c, q)
      end
      expect(changes).to be > 2 * c
    end

    it "performs like a mutex" do
      mutex = described_class.new(collection, key)
      changes = count_leading_edges_from_many_threads(c) do |q|
        mutex.synchronize do
          enqueue_tag_randomly_with_random_sleeps(c, q)
        end
      end
      expect(changes).to be == c
    end

    it "performs like a named mutex" do
      changes = count_leading_edges_from_many_threads(c) do |q|
        mutex = described_class.new(collection, key)
        mutex.synchronize do
          enqueue_tag_randomly_with_random_sleeps(c, q)
        end
      end
      expect(changes).to be == c
    end
  end

  context "with processes" do
    in_child_process_jruby_pending

    it "does not mutex without a mutex" do
      changes = count_leading_edges_from_many_child_processes(c) do |q|
        enqueue_tag_randomly_with_random_sleeps(c, q)
      end
      expect(changes).to be > 2 * c
    end

    it "performs like a mutex" do
      mutex = described_class.new(collection, key)
      changes = count_leading_edges_from_many_child_processes(c) do |q|
        mutex.synchronize do
          enqueue_tag_randomly_with_random_sleeps(c, q)
        end
      end
      expect(changes).to be == c
    end

    it "performs like a named mutex" do
      changes = count_leading_edges_from_many_child_processes(c) do |q|
        mutex = described_class.new(collection, key)
        mutex.synchronize do
          enqueue_tag_randomly_with_random_sleeps(c, q)
        end
      end
      expect(changes).to be == c
    end
  end

end
