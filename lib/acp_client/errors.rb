# frozen_string_literal: true

module AcpClient
  class Error < StandardError; end

  class ConnectionError < Error; end

  class SessionError < Error; end

  class TimeoutError < Error; end

  class ProtocolError < Error; end
end
