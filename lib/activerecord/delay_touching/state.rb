require "activerecord/delay_touching/version"

module ActiveRecord
  module DelayTouching

    # Tracking of the touch state. This class has no class-level data, so you can
    # store per-thread instances in thread-local variables.
    class State
      attr_accessor :nesting

      def initialize
        @records = Hash.new { Set.new }
        @already_updated_records = Hash.new { Set.new }
        @nesting = 0
      end

      def updated(attr, records)
        @records[attr].subtract records
        @records.delete attr if @records[attr].empty?
        @already_updated_records[attr] += records
      end

      # Return the records grouped by the attributes that were touched, and by class:
      # [
      #   [
      #     nil, { Person => [ person1, person2 ], Pet => [ pet1 ] }
      #   ],
      #   [
      #     :neutered_at, { Pet => [ pet1 ] }
      #   ],
      # ]
      def records_by_attrs_and_class
        @records.map { |attrs, records| [attrs, records.group_by(&:class)] }
      end

      # There are more records as long as there is at least one record that is persisted
      def more_records?
        @records.each do |_, set|
          set.each { |record| return true if record.persisted? } # will shortcut on first persisted record found
        end

        false # no persisted records found, so no more records to process
      end

      def add_record(record, *columns)
        # Inferring nil for touch calls with no column specified is creating duplicate DB calls for nested records
        # Grab the default timestamp columns now as opposed to at write time
        columns = record.send(:timestamp_attributes_for_update_in_model) if columns.blank?

        columns.each do |column|
          # Convert column explicitly to string here to keep types consistent
          column = column.to_s
          @records[column] += [ record ] unless @already_updated_records[column].include?(record)
        end
      end

      def clear_records
        @records.clear
        @already_updated_records.clear
      end
    end
  end
end
