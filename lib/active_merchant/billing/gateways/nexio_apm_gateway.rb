# frozen_string_literal: true

require_relative './nexio_base_gateway'

module ActiveMerchant
  module Billing
    class NexioApmGateway < NexioBaseGateway
      self.display_name = 'Nexio AMP'
      self.base_path = '/apm/v3'
      self.abstract_class = false

      OneTimeToken = Struct.new(:token, :iframe_url, :redirect_urls, :button_urls)

      def generate_token(money, options = {})
        post = build_payload(options)
        add_invoice(post, money, options)
        post[:data][:paymentMethod] = options[:payment_method] if options[:payment_method].present?
        add_order_data(post, options)
        post[:customerRedirectUrl] = options[:callback_url] if options[:callback_url].present?
        post[:processingOptions][:saveRecurringToken] = true if options[:save_token]
        resp = commit('token', post)
        return unless resp.success?

        OneTimeToken.new(
          resp.params['token'],
          resp.params['expressIFrameUrl'],
          map_urls(resp.params['redirectUrls']),
          map_urls(resp.params['buttonIFrameUrls'])
        )
      end

      def purchase(money, payment, options = {})
        post = build_payload(options)
        add_invoice(post, money, options)
        if payment.is_a?(Spree::PaymentSource)
          post[:apm] = { token: payment.gateway_payment_profile_id }
        else
          post[:apm] = { token: payment }
        end
        add_order_data(post, options)
        commit('process', post)
      end

      private

      def map_urls(list)
        list.each_with_object({}) { |item, acc| acc[item['paymentMethod']] = item['url'] }
      end
    end
  end
end
