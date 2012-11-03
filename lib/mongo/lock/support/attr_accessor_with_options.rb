require "mongo/lock/support/attr_accessor_writer_visibility"

module Mongo
  module Lock
    module Support
      module AttrAccessorWithOptions

        class << self
          def included(base)
            base.send :include, AttrAccessorWriterVisibility
            base.extend ClassMethods
          end
        end

        module ClassMethods
          def attr_accessor(*names)
            options = names.last.kind_of?(Hash) ? names.pop : { }
            super(*names)
            attr_accessor_writer_visibility options[:writer], *names
          end
        end

      end
    end
  end
end
