# frozen_string_literal: true

require 'net/http'
require 'openssl'

module LicenseFinder
  class GitHub
    CONNECTION_ERRORS = [
      EOFError,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Errno::EINVAL,
      Net::OpenTimeout,
      Net::ProtocolError,
      Net::ReadTimeout,
      Net::HTTPTooManyRequests,
      OpenSSL::OpenSSLError,
      OpenSSL::SSL::SSLError,
      SocketError,
      Timeout::Error
    ].freeze

    class << self
      def license(repo_url)
        owner, repo = repo_url.split('/').slice(-2..-1)
        response = request("https://api.github.com/repos/#{owner}/#{repo}/license")
        response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : {}
      rescue *CONNECTION_ERRORS => e
        raise e, "Unsuccessful calling https://api.github.com/repos/#{owner}/#{repo}/license: #{e}" unless @prepare_no_fail

        {}
      end

      def request(location, limit = 10)
        uri = URI(location)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        response = http.get(uri.request_uri).response
        response.is_a?(Net::HTTPRedirection) && limit.positive? ? request(response['location'], limit - 1) : response
      end
    end
  end
end
