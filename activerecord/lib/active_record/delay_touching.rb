require "active_record/delay_touching/state"

module ActiveRecord
  module DelayTouching
    extend ActiveSupport::Concern

    # Override ActiveRecord::Base#touch.
    def touch(*names)
      if self.class.delay_touching? && !no_touching?
        DelayTouching.add_record(self, names)
        true
      else
        super
      end
    end

    # These get added as class methods to ActiveRecord::Base.
    module ClassMethods
      # Lets you batch up your `touch` calls for the duration of a block.
      #
      # ==== Examples
      #
      #   # Touches Person.first once, not twice, when the block exits.
      #   ActiveRecord::Base.delay_touching do
      #     Person.first.touch
      #     Person.first.touch
      #   end
      #
      def delay_touching(&block)
        DelayTouching.call(&block)
      end

      # Are we currently executing in a delay_touching block?
      def delay_touching?
        DelayTouching.state.nesting > 0
      end
    end

    def self.state
      Thread.current[:delay_touching_state] ||= State.new
    end

    class << self
      delegate :add_record, to: :state
    end

    # Start delaying all touches. When done, apply them. (Unless nested.)
    def self.call
      state.nesting += 1
      begin
        yield
      ensure
        apply if state.nesting == 1
      end
    ensure
      # Decrement nesting even if `apply` raised an error.
      state.nesting -= 1
    end

    # Apply the touches that were delayed.
    def self.apply
      begin
        ActiveRecord::Base.transaction do
          class_attrs_and_records = state.get_and_clear_records
          class_attrs_and_records.each do |class_and_attrs, records|
            klass = class_and_attrs.first
            attrs = class_and_attrs.second
            touch_records klass, attrs, records
          end
        end
      end while state.more_records?
    ensure
      state.clear_already_updated_records
    end

    # Touch the specified records--non-empty set of instances of the same class.
    def self.touch_records(klass, attrs, records)
      if attrs.present?
        current_time = records.first.send(:current_time_from_proper_timezone)
        changes = {}

        attrs.each do |column|
          column = column.to_s
          changes[column] = current_time
          records.each do |record|
            record.instance_eval do
              write_attribute column, current_time
              @changed_attributes.except!(*changes.keys)
            end
          end
        end

        klass.unscoped.where(klass.primary_key => records.sort).update_all(changes)
      end
      state.updated klass, attrs, records
      records.each { |record| record.run_callbacks(:touch) }
    end
  end
end
