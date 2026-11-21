require "http/server"
require "./proxy_config"

module Runcobo
  # Effective request metadata, resolved once from the transport and trusted headers.
  struct RequestInfo
    getter scheme : String
    getter host : String
    getter port : Int32
    getter remote_ip : String?

    def initialize(request : HTTP::Request, *, peer : Socket::IPAddress? = nil, local : Socket::IPAddress? = nil,
                   secure : Bool = false, proxy_config : ProxyConfig = ProxyConfig.new)
      headers = request.headers
      trusted = proxy_config.trusted_proxy?(peer)
      @scheme = secure ? "https" : "http"
      if trusted && (forwarded = last_header(headers, "X-Forwarded-Proto")) && %w(http https).includes?(forwarded)
        @scheme = forwarded
      end
      authority = trusted ? last_header(headers, "X-Forwarded-Host").try { |value| parse_authority(value) } : nil
      authority ||= headers["Host"]?.try { |value| parse_authority(value) }
      @host, explicit_port = authority || {local.try(&.address) || "localhost", local.try(&.port)}
      @port = explicit_port || (ssl? ? 443 : 80)
      if trusted && (forwarded = last_header(headers, "X-Forwarded-Port")) && (number = parse_port(forwarded))
        @port = number
      end
      @remote_ip = resolve_remote_ip(headers, peer, proxy_config)
    end

    def ssl? : Bool
      scheme == "https"
    end

    def protocol : String
      "#{scheme}://"
    end

    def host_with_port : String
      hostname = host.includes?(':') ? "[#{host}]" : host
      port == (ssl? ? 443 : 80) ? hostname : "#{hostname}:#{port}"
    end

    def base_url : String
      protocol + host_with_port
    end

    private def last_header(headers : HTTP::Headers, name : String) : String?
      headers[name]?.try(&.split(',').last.strip.presence)
    end

    private def parse_port(value : String) : Int32?
      return nil unless value.matches?(/\A[0-9]+\z/)
      value.to_i?.try { |number| number if 1 <= number <= 65535 }
    end

    private def parse_authority(value : String) : Tuple(String, Int32?)?
      literal = value.starts_with?('[')
      match = if literal
                /\A\[([0-9A-Fa-f:.]+)\](?::([0-9]+))?\z/.match(value)
              else
                /\A([0-9A-Za-z_](?:[0-9A-Za-z_.-]*[0-9A-Za-z_.])?)(?::([0-9]+))?\z/.match(value)
              end
      return nil unless match
      return nil if literal && !Socket::IPAddress.parse_v6_fields?(match[1])
      port = match[2]?.try { |number| parse_port(number) }
      return nil if match[2]? && !port
      {match[1], port}
    end

    private def address(value : String) : Socket::IPAddress?
      return nil if value.includes?('%')
      Socket::IPAddress.new(value.strip, 0)
    rescue Socket::Error | ArgumentError
      nil
    end

    private def resolve_remote_ip(headers : HTTP::Headers, peer : Socket::IPAddress?, config : ProxyConfig) : String?
      return nil unless peer
      return peer.address unless config.trusted_proxy?(peer)
      if (header = config.client_ip_header) && (value = headers[header]?)
        return address(value).try(&.address) || peer.address
      end
      current = peer
      if forwarded = headers["X-Forwarded-For"]?
        forwarded.split(',').reverse_each do |value|
          break unless config.trusted_proxy?(current)
          candidate = address(value)
          return peer.address unless candidate
          current = candidate
        end
      end
      current.address
    end
  end
end
