require "securerandom"
require "mongo"

require "mongo/lock/support/attr_accessor_with_options"
require "mongo/lock/support/thread_local_attr_accessor"

module Mongo
  module Lock
    class Mutex
      include Support::AttrAccessorWithOptions
      include Support::ThreadLocalAttrAccessor

      class AlreadyAcquiredError < StandardError ; end
      class NotYetAcquiredError < StandardError ; end

      class OperationFailure < StandardError ; end

      class << self
        private

        def derive_methods(*names)
          names.map(&:to_s).each do |name|
            cname = name.gsub(/(?:\A|_)([a-z])/){$1.upcase}
            ex = const_set "#{cname}Failure", Class.new(OperationFailure)
            module_eval <<-CODE, __FILE__, __LINE__
              def try_#{name}
                try { _#{name} }
              end
              def try_#{name}!
                try_#{name} or raise #{ex} and nil
              end
              def #{name}(options = { })
                until_success(options) { try_#{name} }
              end
              def #{name}!(options = { })
                #{name}(options) or raise #{ex} and nil
              end
            CODE
          end
        end
      end

      attr_accessor \
        :collection, :key, :tag_prefix,
        :clock, :ttl, :max_drift,
        writer: :private

      def initialize(collection, key, options = { })
        super()

        self.collection = normalize_collection(collection)
        self.key = key
        self.tag_prefix = options[:tag]       || next_tag_prefix
        self.clock      = options[:clock]     || Time
        self.ttl        = options[:ttl]       || 30
        self.max_drift  = options[:max_drift] || 30
      end

      def tag
        [tag_prefix, ::Process.pid, ::Thread.current.object_id].join(HYPHEN)
      end

      def acquired?
        tick

        _acquired?
      end

      def expires_at
        _expires_at or return
        _expires_at > now or return
        _expires_at
      end

      def to_doc
        coll_find_one(unexpired_query)
      end

      derive_methods :acquire_lock, :refresh_lock, :release_lock, :reload

      def synchronize(options = { })
        acquire_lock!(options[:acquire] || { })
        begin
          yield
        ensure
          try_release_lock
        end
      end

      private

      HYPHEN = "-".freeze
      ID = "_id".freeze
      TAG = "tag".freeze
      EXPIRES_AT = "expires_at".freeze
      OP_LT = "$lt".freeze
      OP_GTE = "$gte".freeze
      OP_SET = "$set".freeze

      private_constant :HYPHEN
      private_constant :ID, :TAG, :EXPIRES_AT
      private_constant :OP_LT, :OP_GTE, :OP_SET

      thread_local_attr_accessor :now, :_expires_at
      private :now, :now=, :_expires_at, :_expires_at=

      def tick
        self.now = Time.at(clock.now.to_i)
      end

      def next_tag_prefix
        SecureRandom.hex(16)
      end

      def id_query
        {ID => key, TAG => tag}
      end

      def unexpired_query
        q = id_query
        q[EXPIRES_AT] = {OP_GTE => now}
        q
      end

      def old_doc_query
        {ID => key, EXPIRES_AT => {OP_LT => now - max_drift}}
      end

      def acquire_doc
        doc = id_query
        doc[EXPIRES_AT] = _next_expires_at
        doc
      end

      def refresh_mod
        {OP_SET => {EXPIRES_AT => _next_expires_at}}
      end

      def _acquired?
        !!expires_at
      end

      def _next_expires_at
        now + ttl
      end

      def try
        tick
        false != yield
      rescue Mongo::OperationFailure, Mongo::ConnectionFailure
        false
      end

      def until_success(options = { })
        sleep = to_sleep_proc(options[:sleep] || 0.1)
        timeout = options[:timeout]

        tick
        cutoff = timeout && now + timeout

        loop do
          tick
          return true if yield
          return false if cutoff && cutoff < now
          sleep.call
        end
      end

      def to_sleep_proc(value)
        case value
          when Proc then value
          when Numeric then ->{sleep value}
          else raise "unknown type of value #{value.inspect}"
        end
      end

      def _acquire_lock
        assert_not_acquired!

        coll_find_and_remove(old_doc_query)
        coll_insert(acquire_doc)
        self._expires_at = _next_expires_at
      end

      def _refresh_lock
        assert_acquired!

        old_doc = coll_find_and_update(unexpired_query, refresh_mod)
        old_doc or return false
        self._expires_at = _next_expires_at
      end

      def _release_lock
        coll_find_and_remove(id_query)
        self._expires_at = nil
      end

      def _reload
        doc = coll_find_one(id_query)
        self._expires_at = doc && doc[EXPIRES_AT]
      end

      def assert_acquired!
        return if _acquired?

        ex = NotYetAcquiredError.new
        ex.set_backtrace(caller)
        raise ex
      end

      def assert_not_acquired!
        return unless _acquired?

        ex = AlreadyAcquiredError.new
        ex.set_backtrace(caller)
        raise ex
      end

      def normalize_collection(coll)
        return coll if coll.write_concern[:w].to_i >= 1
        coll.db.collection(coll.name, w: 1)
      end

      def coll_insert(doc)
        collection.insert(doc)
      end

      def coll_find_and_remove(query)
        collection.find_and_modify(query: query, remove: true)
      end

      def coll_find_and_update(query, update)
        collection.find_and_modify(query: query, update: update)
      end

      def coll_find_one(query)
        collection.find_one(query)
      end

    end
  end
end
