module APN
  class Base < ActiveRecord::Base # :nodoc:

    def self.table_name # :nodoc:
      "apn_devices"
    end

  end
end