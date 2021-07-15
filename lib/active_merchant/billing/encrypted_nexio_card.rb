# frozen_string_literal: true

module ActiveMerchant
  module Billing
    class EncryptedNexioCard < CreditCard
      attr_accessor :encrypted_number, :own_form, :one_time_token

      attr_reader :brand

      def short_year
        year % 100 if year
      end

      private

      def validate_card_brand_and_number
        errors = []

        if empty?(brand)
          errors << [:brand, 'is required'] if own_form
          els
          errors << [:brand, 'is invalid'] unless self.class.card_companies.include?(brand)
        end

        errors << [:encrypted_number, 'is required'] if empty?(encrypted_number)

        errors
      end
    end
  end
end
