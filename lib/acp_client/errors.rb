# frozen_string_literal: true

module AcpClient
  class Error < StandardError; end

  class ConnectionError < Error; end

  class SessionError < Error; end

  class TimeoutError < Error; end

  class ProtocolError < Error
    attr_reader :code, :data

    def initialize(message = nil, code: nil, data: nil)
      super(message)
      @code = code
      @data = data
    end
  end
end
