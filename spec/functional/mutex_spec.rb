require "mongo/lock/mutex"
require "spec_helper"

describe Mongo::Lock::Mutex do
  include InChildProcess

  let(:collection) { db["mutexes", {:w => 0}] }
  let(:key) { "/path-to/some-doc" }
  let(:t0) { Time.at(1_234_567_890, 0_123_456) }
  let(:clock) { Clock.new(t0) }

  def new_mutex(options = { })
    described_class.new(collection, key, {clock: clock}.merge(options))
  end

  def every_nth(n)
    c = 0
    proc { yield if (c += 1) % n == 0 }
  end

  def every_3rd(&block)
    every_nth(3, &block)
  end

  def in_thread(&block)
    Thread.new(&block).value
  end

  def must_rescue(*exes)
    if exes.empty?
      begin
        yield
      rescue => ex
        ex
      else
        nil
      end
    else
      begin
        yield
      rescue *exes => ex
        ex
      else
        raise "not rescued"
      end
    end
  end

  let(:mutex) { new_mutex }
  let(:other_mutex) { new_mutex }



  shared_context "connection failure" do
    before { db.stub(:command).and_raise(Mongo::ConnectionFailure) }
  end



  shared_examples "returns true" do
    it "returns true" do
      expect(result).to be true
    end
  end

  shared_examples "returns false" do
    it "returns false" do
      expect(result).to be false
    end
  end

  shared_examples "mutex not yet acquired error" do
    it "raises NotYetAcquiredError" do
      expect(exception).to be_kind_of Mongo::Lock::Mutex::NotYetAcquiredError
    end
  end

  shared_examples "mutex already acquired error" do
    it "raises AlreadyAcquiredError" do
      expect(exception).to be_kind_of Mongo::Lock::Mutex::AlreadyAcquiredError
    end
  end

  shared_examples "mutex acquire lock failure" do
    it "raises AcquireLockFailure" do
      expect(exception).to be_kind_of Mongo::Lock::Mutex::AcquireLockFailure
    end
  end

  shared_examples "an unacquired mutex" do
    it "is acquired" do
      expect(mutex).to_not be_acquired
    end

    it "sets expires_at" do
      expect(mutex.expires_at).to be nil
    end

    it "writes the doc" do
      expect(mutex.to_doc).to be nil
    end
  end

  shared_examples "a newly-acquired mutex" do
    it "is acquired" do
      expect(mutex).to be_acquired
    end

    it "sets expires_at" do
      expect(mutex.expires_at).to be == Time.at(t0.to_i).getutc + 30
    end

    it "writes the doc" do
      expect(mutex.to_doc).to be == {
        "_id" => key,
        "tag" => mutex.tag,
        "expires_at" => Time.at(t0.to_i).getutc + 30,
      }
    end
  end

  shared_examples "a recently-acquired mutex" do
    it "is acquired" do
      expect(mutex).to be_acquired
    end

    it "sets expires_at" do
      expect(mutex.expires_at).to be == Time.at(t0.to_i).getutc + 20
    end

    it "writes the doc" do
      expect(mutex.to_doc).to be == {
        "_id" => key,
        "tag" => mutex.tag,
        "expires_at" => Time.at(t0.to_i).getutc + 20,
      }
    end
  end



  describe "construction" do
    context "with a non-safe collection" do
      before { expect(collection.write_concern[:w]).to be 0 }

      specify { expect(mutex.collection.write_concern[:w]).to be 1 }
    end
  end



  context "when the mutex is free" do
    describe "#try_acquire_lock" do
      let!(:result) { mutex.try_acquire_lock }

      it_behaves_like "returns true"
      it_behaves_like "a newly-acquired mutex"
    end

    describe "#try_acquire_lock!" do
      let!(:result) { mutex.try_acquire_lock! }

      it_behaves_like "a newly-acquired mutex"
    end
  end

  context "when the mutex is recently acquired" do
    before { clock.travel(-10) { mutex.try_acquire_lock! } }

    describe "#try_acquire_lock" do
      let!(:exception) { must_rescue { mutex.try_acquire_lock } }

      it_behaves_like "mutex already acquired error"
      it_behaves_like "a recently-acquired mutex"
    end

    describe "#try_acquire_lock!" do
      let!(:exception) { must_rescue { mutex.try_acquire_lock! } }

      it_behaves_like "mutex already acquired error"
      it_behaves_like "a recently-acquired mutex"
    end

    describe "#try_refresh_lock" do
      let!(:result) { mutex.try_refresh_lock }

      it_behaves_like "returns true"
      it_behaves_like "a newly-acquired mutex"
    end
  end

  context "when the mutex is recently expired" do
    before { clock.travel(-40) { mutex.try_acquire_lock! } }

    describe "#try_refresh_lock" do
      let!(:exception) { must_rescue { mutex.try_refresh_lock } }

      it_behaves_like "mutex not yet acquired error"
      it_behaves_like "an unacquired mutex"
    end
  end

  context "when another mutex has acquired the lock" do
    before { clock.travel(-10) { other_mutex.try_acquire_lock! } }

    describe "#try_acquire_lock" do
      let!(:result) { mutex.try_acquire_lock }

      it_behaves_like "returns false"
      it_behaves_like "an unacquired mutex"
    end
  end

  context "when the mutex has acquired the lock in another thread" do
    before { clock.travel(-10) { in_thread { mutex.try_acquire_lock! } } }

    describe "#try_acquire_lock" do
      let!(:result) { mutex.try_acquire_lock }

      it_behaves_like "returns false"
      it_behaves_like "an unacquired mutex"
    end
  end

  context "when the mutex has acquired the lock in another process" do
    in_child_process_jruby_pending

    before { clock.travel(-10) { in_child_process { mutex.try_acquire_lock! } } }

    describe "#try_acquire_lock" do
      let!(:result) { mutex.try_acquire_lock }

      it_behaves_like "returns false"
      it_behaves_like "an unacquired mutex"
    end
  end

  context "when the mutex has acquired the lock a long time ago" do
    before { clock.travel(-75) { mutex.try_acquire_lock! } }

    describe "#try_acquire_lock" do
      let!(:result) { mutex.try_acquire_lock }

      it_behaves_like "returns true"
      it_behaves_like "a newly-acquired mutex"
    end
  end

  context "when another mutex has acquired the lock a long time ago" do
    before { clock.travel(-75) { other_mutex.try_acquire_lock! } }

    describe "#try_acquire_lock" do
      let!(:result) { mutex.try_acquire_lock }

      it_behaves_like "returns true"
      it_behaves_like "a newly-acquired mutex"
    end
  end

  context "in case of connection failure" do
    describe "#try_acquire_lock" do
      include_context "connection failure"
      let!(:result) { mutex.try_acquire_lock }

      it_behaves_like "returns false"
      it_behaves_like "an unacquired mutex"
    end

    describe "#try_acquire_lock!" do
      include_context "connection failure"
      let!(:exception) { must_rescue { mutex.try_acquire_lock! } }

      it_behaves_like "mutex acquire lock failure"
      it_behaves_like "an unacquired mutex"
    end
  end



  describe "#try_refresh_lock" do

    context "in case of connection failure" do
      before { mutex.try_acquire_lock! }
      include_context "connection failure"
      let!(:result) { mutex.try_refresh_lock }

      it_behaves_like "returns false"
      it_behaves_like "a newly-acquired mutex"
    end

  end



  describe "#reload" do

    context "within lifetime" do
      before { clock.travel(-10) { mutex.try_acquire_lock! } }

      it "returns true" do
        res = mutex.try_reload
        expect(res).to be true
      end

      it "sets expires_at" do
        mutex.try_reload
        expect(mutex.expires_at).to be == Time.at(t0.to_i).getutc + 20
      end
    end

    context "after expiration" do
      before { clock.travel(-35) { mutex.try_acquire_lock! } }

      it "returns true" do
        res = mutex.try_reload
        expect(res).to be true
      end

      it "sets expires_at" do
        mutex.try_reload
        expect(mutex.expires_at).to be nil
      end
    end

  end



  describe "#try_release_lock" do

    context "within lifetime" do
      before { clock.travel(-10) { mutex.try_acquire_lock! } }

      it "returns true" do
        res = mutex.try_release_lock
        expect(res).to be true
      end

      it "becomes not acquired" do
        mutex.try_release_lock
        expect(mutex).to_not be_acquired
      end

      it "unsets expires_at" do
        mutex.try_release_lock
        expect(mutex.expires_at).to be nil
      end

      it "deletes the doc" do
        mutex.try_release_lock
        expect(mutex.to_doc).to be nil
      end
    end

    context "after expiration" do
      before { clock.travel(-35) { mutex.try_acquire_lock! } }

      it "returns true" do
        res = mutex.try_release_lock
        expect(res).to be true
      end

      it "stays not acquired" do
        mutex.try_release_lock
        expect(mutex).to_not be_acquired
      end

      it "unsets expires_at" do
        mutex.try_release_lock
        expect(mutex.expires_at).to be nil
      end

      it "deletes the doc" do
        mutex.try_release_lock
        expect(mutex.to_doc).to be nil
      end
    end

  end



  describe "#acquire_lock" do

    context "without contention" do
      it "returns true immediately" do
        res = mutex.acquire_lock(sleep: every_3rd { raise "sleep" })
        expect(res).to be true
      end

      it "becomes acquired immediately" do
        mutex.acquire_lock(sleep: every_3rd { raise "sleep" })
        expect(mutex).to be_acquired
      end
    end

    context "with contention" do
      before do
        other_mutex.try_acquire_lock!
      end

      context "without timeout" do
        it "detects the contention" do
          expect { mutex.acquire_lock(sleep: every_3rd { raise "sleep" }) }
            .to raise_error "sleep"
          expect(mutex).to_not be_acquired
        end

        it "returns true once the contention goes away" do
          res = mutex.acquire_lock(sleep: every_3rd { other_mutex.try_release_lock! })
          expect(res).to be true
        end

        it "becomes acquired once the contention goes away" do
          mutex.acquire_lock(sleep: every_3rd { other_mutex.try_release_lock! })
          expect(mutex).to be_acquired
        end
      end

      context "with timeout" do
        it "detects the contention" do
          expect { mutex.acquire_lock(timeout: 3, sleep: every_3rd { raise "sleep" }) }
            .to raise_error "sleep"
          expect(mutex).to_not be_acquired
        end

        it "returns false if it takes too long" do
          res = mutex.acquire_lock(timeout: 3, sleep: every_3rd { clock.travel 1 })
          expect(res).to be false
        end

        it "does not become acquired if it takes too long" do
          mutex.acquire_lock(timeout: 3, sleep: every_3rd { clock.travel 1 })
          expect(mutex).to_not be_acquired
        end
      end

    end

  end



  describe "#synchronize" do

    context "without contention" do
      it "calls the block" do
        set = false
        mutex.synchronize { set = true }
        expect(set).to be true
      end

      it "sets the doc inside the block" do
        doc = mutex.synchronize { mutex.to_doc }
        expect(doc).to be == {
          "_id" => key,
          "tag" => mutex.tag,
          "expires_at" => Time.at(t0.to_i).getutc + 30,
        }
      end

      it "deletes the doc" do
        mutex.synchronize { }
        expect(mutex.to_doc).to be nil
      end
    end

  end



end
