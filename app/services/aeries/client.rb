# frozen_string_literal: true

module Aeries
  # SCH3 — the Aeries SIS API client SCAFFOLD. Security posture (all enforced
  # here, none optional):
  #   * DISABLED BY DEFAULT: Aeries::Client.enabled? is true only when BOTH
  #     AERIES_BASE_URL and AERIES_API_KEY are configured (the SES/ClientMessaging
  #     precedent — configuring real credentials IS the enable switch). No real
  #     calls are possible until SMJUHSD signs the data-sharing authorization
  #     and ops sets the env values.
  #   * TLS ONLY: an http:// base URL is rejected at call time, not just ignored.
  #   * HOST PINNING: every request goes to the configured host — the path is
  #     joined server-side, callers cannot smuggle another origin.
  #   * VALUES-FREE LOGGING: log lines carry endpoint + status + timing only,
  #     never student data and never the key.
  #   * The Aeries certificate key rides the AERIES-CERT header per the Aeries
  #     API convention.
  class Client
    TIMEOUT_SECONDS = 15

    class Disabled < StandardError; end
    class InsecureEndpoint < StandardError; end

    def self.enabled?
      ENV['AERIES_BASE_URL'].present? && ENV['AERIES_API_KEY'].present?
    end

    def get(path)
      raise Disabled, 'Aeries is not configured (AERIES_BASE_URL/AERIES_API_KEY unset)' unless self.class.enabled?

      base = URI.parse(ENV['AERIES_BASE_URL'])
      raise InsecureEndpoint, 'Aeries requires https' unless base.is_a?(URI::HTTPS)

      uri = URI.join("#{base}/", path.to_s.sub(%r{\A/}, ''))
      raise InsecureEndpoint, 'host mismatch' unless uri.host == base.host

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = TIMEOUT_SECONDS
      http.read_timeout = TIMEOUT_SECONDS

      request = Net::HTTP::Get.new(uri)
      request['AERIES-CERT'] = ENV['AERIES_API_KEY']
      request['Accept'] = 'application/json'

      response = http.request(request)
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)
      Rails.logger.info("[aeries] GET #{uri.path} -> #{response.code} (#{elapsed}s)") # values-free
      raise "Aeries HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end
