class <%= redemption_class_name %> < ActiveRecord::Base
  belongs_to :<%= singular_name %>, :counter_cache => 'redemptions_count'
  belongs_to :user

  validates_presence_of :user_id, :<%= singular_name %>_id
end
