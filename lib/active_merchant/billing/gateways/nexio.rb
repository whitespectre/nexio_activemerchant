# frozen_string_literal: true

require 'json'

module ActiveMerchant
  module Billing
    class NexioGateway < Gateway
      self.test_url = 'https://api.nexiopaysandbox.com'
      self.live_url = 'https://api.nexiopay.com'

      self.supported_countries = %w[CA US]
      self.default_currency = 'USD'
      self.supported_cardtypes = %i[visa master american_express discover]

      self.homepage_url = 'https://nex.io'
      self.display_name = 'Nexio'

      STANDARD_ERROR_CODE_MAPPING = {}.freeze

      OneTimeToken = Struct.new(:token, :expiration, :fraud_url)

      def initialize(options = {})
        requires!(options, :merchant_id, :auth_token)
        super
      end

      def generate_token(options = {})
        post = build_payload(options)
        add_currency(post, options)
        add_order_data(post, options)
        add_card_data(post, options)
        resp = commit('token', post)
        return unless resp.success?

        token, expiration, fraud_url = resp.params.values_at('token', 'expiration', 'fraudUrl')
        OneTimeToken.new(token, Time.parse(expiration), fraud_url)
      end

      def purchase(money, payment, options = {})
        post = build_payload(options)
        post[:processingOptions] ||= {}
        post[:processingOptions][:verboseResponse] = true if test?
        post[:processingOptions][:customerRedirectUrl] = options[:three_d_callback_url] if options.key?(:three_d_callback_url)
        post[:processingOptions][:check3ds] = options[:three_d_secure]
        post[:processingOptions][:paymentType] = options[:payment_type] if options.key?(:payment_type)
        add_invoice(post, money, options)
        add_payment(post, payment, options)
        add_order_data(post, options)
        commit('process', post)
      end

      def authorize(money, payment, options = {})
        purchase(money, payment, options.merge(payload: options.fetch(:payload, {}).merge(isAuthOnly: true)))
      end

      def capture(money, authorization, _options = {})
        commit('capture', { id: authorization, data: { amount: amount(money).to_f } })
      end

      def refund(money, authorization, _options = {})
        commit('refund', { id: authorization, data: { amount: amount(money).to_f } })
      end
      alias credit refund

      def void(authorization, _options = {})
        commit('void', { id: authorization })
      end

      def verify(credit_card, options = {})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        false
      end

      def scrub(transcript)
        transcript
      end

      def store(payment, options = {})
        post = build_payload(options)
        add_card_details(post, payment, options)
        add_currency(post, options)
        add_order_data(post, options)
        resp = commit('saveCard', post)
        return unless resp.success?

        resp.params.fetch('token', {}).fetch('token', nil)
      end

      def set_webhooks(data)
        post = { merchantId: options[:merchant_id].to_s }
        if data.is_a?(String)
          post[:webhooks] = {
            TRANSACTION_AUTHORIZED: { url: data },
            TRANSACTION_CAPTURED: { url: data }
          }
        else
          webhooks = {}
          webhooks[:TRANSACTION_AUTHORIZED] = { url: data[:authorized] } if data.key?(:authorized)
          webhooks[:TRANSACTION_CAPTURED] = { url: data[:captured] } if data.key?(:captured)
          post[:webhooks] = webhooks
        end
        commit('webhook', post)
      end

      def set_secret
        commit('secret', { merchantId: options[:merchant_id].to_s }).params['secret']
      end

      def get_transaction(id)
        parse(ssl_get(action_url("/transaction/v3/paymentId/#{id}"), base_headers))
      rescue ResponseError => e
      end

      private

      def add_invoice(post, money, options)
        post[:data][:amount] = amount(money).to_f
        add_currency(post, options)
      end

      def add_currency(post, options)
        post[:data][:currency] = options[:currency] if options.key?(:currency)
      end

      def add_order_data(post, options)
        if customer = options[:customer]
          case customer
          when String
            post[:data][:customer][:email] = customer
          when Hash
            post[:data][:customer].merge!({
                                            firstName: customer[:first_name],
                                            lastName: customer[:last_name],
                                            email: customer[:email]
                                          })
          end
        end

        if order = options[:order]
          add_cart(post, order[:line_items]) if order.key?(:line_items)
          post[:data][:customer][:orderNumber] = order[:number] if order.key?(:number)
          post[:data][:customer][:orderDate] = order[:date] if order.key?(:date)
        end

        add_address(post, options[:billing_address], :billTo)
        add_address(post, options[:address], :shipTo)
        if phone = options.fetch(:address, options.fetch(:billing_address, {}))[:phone]
          post[:data][:customer][:phone] = phone
        end
      end

      def add_cart(post, list)
        items = list.map do |item|
          {
            item: item[:id],
            description: item[:description],
            quantity: item.fetch(:quantity, 1),
            price: amount(item[:price]).to_f,
            type: item.fetch(:type, :sale)
          }
        end
        post[:data][:cart] = { items: items }
      end

      def add_address(post, data, prefix)
        return post if data.blank?

        post[:data][:customer].merge!({
                                        "#{prefix}AddressOne": data[:address1],
                                        "#{prefix}AddressTwo": data[:address2],
                                        "#{prefix}City": data[:city],
                                        "#{prefix}Country": data[:country],
                                        "#{prefix}Phone": data[:phone],
                                        "#{prefix}Postal": data[:zip],
                                        "#{prefix}State": data[:state]
                                      })
      end

      def add_payment(post, payment, options)
        post[:tokenex] = token_from(payment)
        if payment.is_a?(Spree::CreditCard)
          post[:card] = {
            cardHolderName: payment.name,
            cardType: payment.brand
          }
        end
        post[:processingOptions] ||= {}
        post[:processingOptions][:merchantId] = self.options[:merchant_id].to_s
        post[:processingOptions][:saveCardToken] = options[:save_credit_card] if options.key?(:save_credit_card)
      end

      def token_from(payment)
        return { token: payment } if payment.is_a?(String)

        {
          token: payment.gateway_payment_profile_id,
          lastFour: payment.last_digits,
          cardType: payment.brand
        }
      end

      def add_card_data(post, options)
        if card = options[:card]
          post[:card] = {
            cardHolderName: card[:name],
            expirationMonth: card[:month],
            expirationYear: card[:year]
          }
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

      def parse(body)
        JSON.parse(body)
      rescue StandardError
        {}
      end

      def commit(action, parameters)
        payload = parse(ssl_post(commit_action_url(action, parameters), post_data(action, parameters), base_headers))

        Response.new(
          response_status(action, payload),
          nil,
          payload,
          authorization: authorization_from(payload),
          avs_result: build_avs_result(payload['avsResults']),
          cvv_result: build_cvv_result(payload['cvcResults']),
          test: test?,
          network_transaction_id: payload['id']
        )
      rescue ResponseError => e
        error_payload = parse(e.response.body)
        Response.new(
          false,
          error_payload['message'],
          {},
          test: test?,
          error_code: error_payload['error'] || e.response.code.to_i
        )
      end

      def response_status(action, payload)
        case action
        when 'process' then authorization_from(payload).present?
        else
          true
        end
      end

      def authorization_from(payload)
        payload.fetch('id', nil)
      end

      def post_data(_action, parameters = {})
        parameters.to_json
      end

      def commit_action_url(action, _parameters)
        path = case action
        when 'webhook' then '/webhook/v3/config'
        when 'secret' then '/webhook/v3/secret'
        else
          "/pay/v3/#{action}"
        end
        action_url(path)
      end

      def action_url(path)
        "#{test? ? test_url : live_url}#{path}"
      end

      def build_avs_result(data)
        return if data.blank?

        AVSResult.new(street_match: data['matchAddress'], postal_match: data['matchPostal'])
      end

      def build_cvv_result(data)
        return if data.blank?

        CVVResult.new(data.fetch('gatewayMessage', {}).fetch('cvvresponse', nil))
      end

      def build_payload(options)
        { data: { customer: {} } }.merge!(options.fetch(:payload, {}))
      end

      def base_headers(custom = {})
        { Authorization: "Basic #{options[:auth_token]}" }
      end
    end
  end
end
