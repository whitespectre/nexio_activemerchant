# frozen_string_literal: true

module NexioActivemerchant
  Transaction = Struct.new(:data) do
    def status
      data['transactionStatus']
    end

    def amount
      data['amount'].to_d
    end
  end
end
