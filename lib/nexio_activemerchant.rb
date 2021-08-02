# frozen_string_literal: true

require 'activemerchant'
require 'active_merchant/billing/rails'
require 'active_merchant/billing/encrypted_nexio_card'
require 'active_merchant/billing/gateways/nexio'
require 'nexio_activemerchant/version'

module NexioActivemerchant
  class Error < StandardError; end
end
