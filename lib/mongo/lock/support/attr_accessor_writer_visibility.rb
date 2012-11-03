module Mongo
  module Lock
    module Support
      module AttrAccessorWriterVisibility

        class << self
          def included(base)
            base.extend ClassMethods
          end
        end

        module ClassMethods
          def attr_accessor_writer_visibility(visibility, *names)
            return if visibility.nil?
            visibilities = [:protected, :private]
            visibilities.include?(visibility) or raise ArgumentError,
                "bad writer visibility"
            send visibility, *names.map{|n| :"#{n}="}
          end
        end

      end
    end
  end
end
