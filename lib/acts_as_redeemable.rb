require 'md5'
module Squeejee  #:nodoc:
  module Acts  #:nodoc:
    module Redeemable  #:nodoc:
      def self.included(base)
        base.extend(ClassMethods)
      end
      # This act provides the capabilities for redeeming and expiring models. Useful for things like
      # coupons, invitations, and special offers.
      #
      # Coupon example:
      #
      #   class Coupon < ActiveRecord::Base
      #     acts_as_redeemable :valid_for => 30.days, :code_length => 8 # optional expiration, code length
      #   end
      #
      #
      #   c = Coupon.new
      #   c.user_id = 1 # The user who created the coupon 
      #   c.save
      #   c.code 
      #       
      #   # "4D9110A3"
      module ClassMethods
        # Configuration options are:
        #
        # * +valid_for+ - specifies the duration until redeemable expire. Default is no expiration
        # * +code_length+ - set the length of the generated unique code. Default is six alphanumeric characters
        # * +allow_custom+ - allow this redeemable to be created with a custom code.  The code must be unique, or will fail validation.
        # * example: <tt>acts_as_redeemable :valid_for => 30.days, :code_length => 8</tt>
        def acts_as_redeemable(options = {})
          unless redeemable? # don't let AR call this twice
            cattr_accessor :valid_for
            cattr_accessor :code_length
            cattr_accessor :allow_custom

            before_create :setup_new
            
            self.valid_for = options[:valid_for] unless options[:valid_for].nil?
            self.code_length = (options[:code_length].nil? ? 6 : options[:code_length])
            self.allow_custom = (options[:allow_custom].nil? ? false : options[:allow_custom])
            
            if self.allow_custom
              self.validates_uniqueness_of :code, :allow_blank => true
            end
          end
          
          include InstanceMethods
          if options[:multi_use]
            include MultiUseRedeemableInstanceMethods
          else
            include SingleUseRedeemableInstanceMethods
          end
          
          # Generates an alphanumeric code using an MD5 hash
          # * +code_length+ - number of characters to return
          def generate_code(code_length=6)
            chars = ("a".."z").to_a + ("1".."9").to_a 
            new_code = Array.new(code_length, '').collect{chars[rand(chars.size)]}.join
            Digest::MD5.hexdigest(new_code)[0..(code_length-1)].upcase
          end

          # Generates unique code based on +generate_code+ method
          def generate_unique_code
            begin
              new_code = generate_code(self.code_length)
            end until !active_code?(new_code)
            new_code
          end
          
          # Checks the database to ensure the specified code is not taken
          def active_code?(code)
            find :first, :conditions => {:code => code}
          end

        end
        
        def redeemable? #:nodoc:
          self.included_modules.include?(InstanceMethods)
        end
      end
      
      module SingleUseRedeemableInstanceMethods

        # Marks the redeemable redeemed by the given user id
        # * +redeemed_by_id+ - id of redeeming user
        def redeem!(redeemed_by)
          unless self.redeemed? or self.expired?
            redeemed_by_id = redeemed_by.kind_of?(ActiveRecord::Base) ? redeemed_by.id : redeemed_by.to_i
            self.update_attributes(:redeemed_by_id => redeemed_by_id, :redeemed_at => Time.now)
            self.after_redeem
          end
        end

        # Returns whether or not the redeemable has been redeemed
        def redeemed?
          self.redeemed_at?
        end

      end
      
      module MultiUseRedeemableInstanceMethods
        # Adds the give redeemer to this redeemable's list of
        # +redemption+ records
        def redeem!(redeemed_by)
          unless self.expired?
            redeemed_by_id = redeemed_by.kind_of?(ActiveRecord::Base) ? redeemed_by.id : redeemed_by.to_i
            self.redemptions.create(:user_id => redeemed_by_id)
            self.after_redeem
          end
        end

        # Returns whether or not the redeemable has been redeemed
        def redeemed?
          self.redemptions_count > 0
        end
        
        # Returns whether a user has already redeemed this redeemable
        def redeemed_by?(user)
          user_id = user.kind_of?(ActiveRecord::Base) ? user.id : user.to_i
          redeemers.exists?(user_id)
        end
      end
      
      module InstanceMethods

        # Returns whether or not the redeemable has expired
        def expired?
          self.expires_on? and self.expires_on < Time.now
        end

        def setup_new #:nodoc:
          unless self.class.allow_custom && self.code
            self.code = self.class.generate_unique_code
          end
          
          unless self.class.valid_for.nil? or self.expires_on?
            self.expires_on = self.created_at + self.class.valid_for
          end
        end
        
        # Callback for business logic to implement after redemption
        def after_redeem() end

      end
    end
  end
end
