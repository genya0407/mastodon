# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PrivateAddressCheck do
  describe 'private_address?' do
<<<<<<< HEAD
    it 'returns true for private addresses' do
      # rubocop:disable RSpec/ExpectActual
      expect(
        [
          '192.168.1.7',
          '0.0.0.0',
          '127.0.0.1',
          '::ffff:0.0.0.1',
        ]
      ).to all satisfy('return true') { |addr| described_class.private_address?(IPAddr.new(addr)) }
      # rubocop:enable RSpec/ExpectActual
=======
    let(:private_ips) { %w(192.168.1.7 0.0.0.0 127.0.0.1 ::ffff:0.0.0.1) }

    it 'returns true for private addresses' do
      expect(private_ips)
        .to all(satisfy { |addr| described_class.private_address?(IPAddr.new(addr)) })
>>>>>>> origin/trunk
    end
  end
end
