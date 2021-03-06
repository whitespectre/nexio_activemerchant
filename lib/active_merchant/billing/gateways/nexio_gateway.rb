# frozen_string_literal: true

require_relative './nexio_base_gateway'

module ActiveMerchant
  module Billing
    class NexioGateway < NexioBaseGateway
      self.display_name = 'Nexio'
      self.base_path = '/pay/v3'
      self.abstract_class = false

      OneTimeToken = Struct.new(:token, :expiration, :fraud_url)

      def generate_token(options = {})
        post = build_payload(options)
        post[:data][:allowedCardTypes] = %w[amex discover jcb mastercard visa]
        add_currency(post, options)
        add_order_data(post, options)
        add_card_data(post, options)
        resp = commit('token', post)
        return unless resp.success?

        token, expiration, fraud_url = resp.params.values_at('token', 'expiration', 'fraudUrl')
        OneTimeToken.new(token, Time.parse(expiration), fraud_url)
      end

      def purchase(money, source, options = {})
        post = build_payload(options)
        add_invoice(post, money, options)
        add_payment(post, source, options)
        add_order_data(post, options)
        commit('process', post)
      end

      def authorize(money, source, options = {})
        purchase(money, source, options.merge(payload: options.fetch(:payload, {}).merge(isAuthOnly: true)))
      end

      def verify(credit_card, options = {})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def store(source, options = {})
        post = build_payload(options)
        post[:merchantId] ||= options[:merchant_id]
        add_card_details(post, source, options)
        add_currency(post, options)
        add_order_data(post, options)
        resp = commit('saveCard', post)
        return unless resp.success?

        resp.params.fetch('token', {}).fetch('token', nil)
      end

      private

      def add_payment(post, source, options)
        post[:tokenex] = token_from(source)
        post[:card] ||= {}
        if source.is_a?(Spree::CreditCard)
          post[:card][:cardHolderName] = source.name
          post[:card][:cardType] = source.brand
        end
        post[:card][:securityCode] = options.dig(:card, :cvv) if options.dig(:card, :cvv)
        post[:processingOptions][:saveCardToken] = options[:save_credit_card] if options.key?(:save_credit_card)
        if options[:three_d_callback_url].present?
          post[:processingOptions][:customerRedirectUrl] = options[:three_d_callback_url]
        end
        post[:processingOptions][:check3ds] = options[:three_d_secure]
        post[:processingOptions][:paymentType] = options[:payment_type] if options[:payment_type].present?
      end

      def token_from(source)
        return { token: source } if source.is_a?(String)

        {
          token: source.gateway_payment_profile_id,
          lastFour: source.last_digits,
          cardType: source.brand
        }
      end

      def add_card_data(post, options)
        if card = options[:card]
          post[:card] ||= {}
          post[:card].merge!(
            cardHolderName: card[:name],
            expirationMonth: card[:month],
            expirationYear: card[:year]
          )
        end
      end

      def add_card_details(post, payment, _options)
        if payment.is_a?(EncryptedNexioCard)
          raise ArgumentError, 'The provided card is invalid' unless payment.valid?

          post[:card] = {
            cardHolderName: payment.name,
            encryptedNumber: payment.encrypted_number,
            expirationMonth: payment.month,
            expirationYear: payment.short_year,
            cardType: payment.brand,
            securityCode: payment.verification_value
          }
          post[:token] = payment.one_time_token
        else
          raise ArgumentError, "Only #{EncryptedNexioCard} payment method is supported to store cards"
        end
      end
    end
  end
end
