require "mongo/lock/support/attr_accessor_writer_visibility"

module Mongo
  module Lock
    module Support
      module ThreadLocalAttrAccessor

        class << self
          def included(base)
            base.send :include, AttrAccessorWriterVisibility
            base.extend ClassMethods
          end
        end

        module ClassMethods
          def thread_local_attr_accessor(*names)
            options = names.last.kind_of?(Hash) ? names.pop : { }
            names.each do |name|
              module_eval <<-CODE, __FILE__, __LINE__ + 1
                def #{name}
                  _thread_local_current_attributes[:#{name}]
                end
                def #{name}=(value)
                  _thread_local_current_attributes[:#{name}] = value
                end
              CODE
            end
            attr_accessor_writer_visibility options[:writer], *names
          end
        end

        def initialize(*)
          super
          _initialize_thread_local_attributes
        end

        private

        attr_accessor :_thread_local_attributes, :_thread_local_attributes_mutex

        def _initialize_thread_local_attributes
          self._thread_local_attributes = { }
          self._thread_local_attributes_mutex = ::Mutex.new
        end

        def _thread_local_current_attributes
          tag = [::Process.pid, ::Thread.current.object_id]
          _thread_local_attributes_mutex.synchronize do
            _thread_local_attributes[tag] ||= { }
          end
        end

      end
    end
  end
end
