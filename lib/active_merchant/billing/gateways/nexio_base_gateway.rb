# frozen_string_literal: true

require 'json'

module ActiveMerchant
  module Billing
    class NexioBaseGateway < Gateway
      self.test_url = 'https://api.nexiopaysandbox.com'
      self.live_url = 'https://api.nexiopay.com'

      self.supported_countries = %w[CA US]
      self.default_currency = 'USD'
      self.supported_cardtypes = %i[visa master american_express discover]
      self.homepage_url = 'https://nex.io'
      self.abstract_class = true

      class_attribute :base_path
      self.base_path = ''

      def initialize(options = {})
        requires!(options, :merchant_id, :auth_token)
        super
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

      def supports_scrubbing?
        false
      end

      def scrub(transcript)
        transcript
      end

      def set_webhooks(data)
        post = { merchantId: options[:merchant_id].to_s }
        if data.is_a?(String)
          post[:webhooks] = {
            TRANSACTION_AUTHORIZED: { url: data },
            TRANSACTION_CAPTURED: { url: data },
            TRANSACTION_SETTLED: { url: data }
          }
        else
          webhooks = {}
          webhooks[:TRANSACTION_AUTHORIZED] = { url: data[:authorized] } if data.key?(:authorized)
          webhooks[:TRANSACTION_CAPTURED] = { url: data[:captured] } if data.key?(:captured)
          webhooks[:TRANSACTION_SETTLED] = { url: data[:settled] } if data.key?(:settled)
          post[:webhooks] = webhooks
        end
        commit('webhook', post)
      end

      def set_secret
        commit('secret', { merchantId: options[:merchant_id].to_s }).params['secret']
      end

      private

      def build_payload(params)
        result = params.fetch(:payload, {}).deep_dup
        result[:data] ||= {}
        result[:data][:customer] ||= {}
        result[:processingOptions] ||= {}
        result[:processingOptions][:merchantId] ||= options[:merchant_id]
        result[:processingOptions][:verboseResponse] = true if test?
        result
      end

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
            post[:data][:customer][:customerRef] = customer
          when Hash
            post[:data][:customer].merge!({
                                            firstName: customer[:first_name],
                                            lastName: customer[:last_name],
                                            email: customer[:email],
                                            customerRef: customer[:email]
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

        {
          AddressOne: :address1, AddressTwo: :address2, City: :city,
          Country: :country, Phone: :phone, Postal: :zip, State: :state
        }.each do |suffix, key|
          post[:data][:customer]["#{prefix}#{suffix}"] = data[key]
        end
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
        logger&.error e.response.body
        error_payload = parse(e.response.body)
        Response.new(
          false,
          error_payload['message'],
          {},
          test: test?,
          error_code: error_payload['error'] || e.response.code.to_i
        )
      end

      def post_data(_action, post = {})
        JSON.dump(post)
      end

      def parse(body)
        JSON.parse(body)
      rescue StandardError
        {}
      end

      def commit_action_url(action, _parameters)
        path = case action
        when 'webhook' then '/webhook/v3/config'
        when 'secret' then '/webhook/v3/secret'
        else
          "#{self.class.base_path}/#{action}"
        end
        action_url(path)
      end

      def action_url(path)
        "#{test? ? test_url : live_url}#{path}"
      end

      def base_headers(custom = {})
        { Authorization: "Basic #{options[:auth_token]}" }
      end

      def response_status(action, payload)
        case action
        when 'process' then %w(authOnlyPending authorizedPending pending authOnly settled).include?(payload['transactionStatus'])
        else
          true
        end
      end

      def authorization_from(payload)
        payload.fetch('id', nil)
      end

      def build_avs_result(data)
        return if data.blank?

        AVSResult.new(street_match: data['matchAddress'], postal_match: data['matchPostal'])
      end

      def build_cvv_result(data)
        return if data.blank?

        CVVResult.new(data.fetch('gatewayMessage', {}).fetch('cvvresponse', nil))
      end
    end
  end
end
