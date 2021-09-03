# frozen_string_literal: true

module ActiveMerchant
  module Billing
    class EncryptedNexioCard < CreditCard
      ALLOWED_CARD_BRANDS = %w(amex discover jcb mastercard visa).freeze

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
        elsif !ALLOWED_CARD_BRANDS.include?(brand)
          errors << [:brand, 'is invalid']
        end

        errors << [:encrypted_number, 'is required'] if empty?(encrypted_number)

        errors
      end
    end
  end
end
