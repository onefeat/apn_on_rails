# Represents the message you wish to send.
# An APN::Notification belongs to an APN::Device.
#
# Example:
#   apn = APN::Notification.new
#   apn.badge = 5
#   apn.sound = 'my_sound.aiff'
#   apn.alert = 'Hello!'
#   apn.device = APN::Device.find(1)
#   apn.save
#
# To deliver call the following method:
#   APN::Notification.send_notifications
#
# As each APN::Notification is sent the <tt>sent_at</tt> column will be timestamped,
# so as to not be sent again.
class APN::Notification < APN::Base
  include ::ActionView::Helpers::TextHelper
  extend ::ActionView::Helpers::TextHelper
  serialize :custom_properties

  def self.table_name # :nodoc:
    "apn_notifications"
  end

  belongs_to :device, :class_name => 'APN::Device'

  attr_accessible :device_id

  # Stores the text alert message you want to send to the device.
  #
  # If the message is over 150 characters long it will get truncated
  # to 150 characters with a <tt>...</tt>
  def alert=(message)
    if !message.blank? && message.size > 150
      message = truncate(message, :length => 150)
    end
    write_attribute('alert', message)
  end

  # Creates a Hash that will be the payload of an APN.
  #
  # Example:
  #   apn = APN::Notification.new
  #   apn.badge = 5
  #   apn.sound = 'my_sound.aiff'
  #   apn.alert = 'Hello!'
  #   apn.apple_hash # => {"aps" => {"badge" => 5, "sound" => "my_sound.aiff", "alert" => "Hello!"}}
  #
  # Example 2:
  #   apn = APN::Notification.new
  #   apn.badge = 0
  #   apn.sound = true
  #   apn.custom_properties = {"typ" => 1}
  #   apn.apple_hast # => {"aps" => {"badge" => 0}}
  def apple_hash
    result = {}
    result['aps'] = {}
    result['aps']['alert'] = self.alert if self.alert
    result['aps']['badge'] = self.badge.to_i if self.badge
    if self.sound
      result['aps']['sound'] = self.sound if self.sound.is_a? String
      result['aps']['sound'] = "1.aiff" if self.sound.is_a?(TrueClass)
    end
    if self.custom_properties
      self.custom_properties.each do |key,value|
        result["#{key}"] = "#{value}"
      end
    end
    result
  end

  # Creates the JSON string required for an APN message.
  #
  # Example:
  #   apn = APN::Notification.new
  #   apn.badge = 5
  #   apn.sound = 'my_sound.aiff'
  #   apn.alert = 'Hello!'
  #   apn.to_apple_json # => '{"aps":{"badge":5,"sound":"my_sound.aiff","alert":"Hello!"}}'
  def to_apple_json
    self.apple_hash.to_json
  end

  # Creates the binary message needed to send to Apple.
  def message_for_sending
    json = self.to_apple_json
    message = "\0\0 #{self.device.to_hexa}\0#{json.length.chr}#{json}"
    raise APN::Errors::ExceededMessageSizeError.new(message) if message.size.to_i > 256
    message
  end

  class << self

    # Opens a connection to the Apple APN server and attempts to batch deliver
    # an Array of notifications.
    #
    # This method expects an Array of APN::Notifications. If no parameter is passed
    # in then it will use the following:
    #   APN::Notification.all(:conditions => {:sent_at => nil})
    #
    # As each APN::Notification is sent the <tt>sent_at</tt> column will be timestamped,
    # so as to not be sent again.
    #
    # This can be run from the following Rake task:
    #   $ rake apn:notifications:deliver
    def send_notifications(notifications = APN::Notification.all(:conditions => {:sent_at => nil}))
      begin
        APN::Connection.open_for_delivery do |conn, sock|
          #devs = APN::Device.all
          unset = APN::Notification.where(:sent_at => nil).order(:device_id, :created_at)
          unset.each do |noty|
            Rails.logger.debug "Sending notification ##{noty.id}"
            puts "Sending notification ##{noty.id}"
            begin
              conn.write(noty.message_for_sending)
              noty.sent_at = Time.now
              noty.save
            rescue APN::Errors::ExceededMessageSizeError
              noty.sent_at = Time.now
              noty.save
            rescue => e
              Rails.logger.error "Cannot send notification ##{noty.id}: " + e.message
              puts "Cannot send notification ##{noty.id}: " + e.message
              #noty.device.delete if noty.device
              noty.sent_at = Time.now
              noty.save
              return if e.message == "Broken pipe"
            end
          end
        end
      rescue Exception => e
        log_connection_exception(e)
      end
    end

  end # class << self

  protected
  def self.log_connection_exception(ex)
    puts ex.message
  end

end # APN::Notification
