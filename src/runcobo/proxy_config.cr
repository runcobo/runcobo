require "socket"

module Runcobo
  # Trust is explicit and scoped to a handler/server, never process-global.
  class ProxyConfig
    getter client_ip_header : String?
    @networks : Array(ProxyNetwork)

    def initialize(*, trusted_proxies : Array(String) = [] of String, @client_ip_header : String? = nil)
      if header = client_ip_header
        unless header.matches?(/\A[!#$%&'*+.^_`|~0-9A-Za-z-]+\z/)
          raise ArgumentError.new("client_ip_header must be a valid header name")
        end
      end
      @networks = trusted_proxies.map { |value| ProxyNetwork.new(value.strip) }
    end

    def trusted_proxy?(address : Socket::IPAddress?) : Bool
      !!(address && @networks.any? { |network| network.includes?(address) })
    end

    private struct ProxyNetwork
      @number : UInt128
      @bits : Int32
      @shift : Int32

      def initialize(value : String)
        parts = value.split('/', 2)
        @number, @bits = self.class.address_data(parts.first)
        prefix = @bits
        if suffix = parts[1]?
          raise ArgumentError.new("Invalid trusted proxy range: #{value}") unless suffix.matches?(/\A[0-9]+\z/)
          prefix = suffix.to_i? || -1
        end
        raise ArgumentError.new("Invalid trusted proxy range: #{value}") unless 0 <= prefix <= @bits
        @shift = @bits - prefix
        @number = @shift == @bits ? 0_u128 : @number >> @shift
      end

      def includes?(address : Socket::IPAddress) : Bool
        number, bits = self.class.address_data(address.address)
        bits == @bits && (@shift == @bits || number >> @shift == @number)
      end

      def self.address_data(value : String) : Tuple(UInt128, Int32)
        if fields = Socket::IPAddress.parse_v4_fields?(value)
          {fields.reduce(0_u128) { |number, field| (number << 8) | field }, 32}
        elsif !value.includes?('%') && (fields = Socket::IPAddress.parse_v6_fields?(value))
          {fields.reduce(0_u128) { |number, field| (number << 16) | field }, 128}
        else
          raise ArgumentError.new("Invalid trusted proxy address: #{value}")
        end
      end
    end
  end
end
