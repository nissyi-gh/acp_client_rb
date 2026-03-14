# frozen_string_literal: true

require "test_helper"

class TestErrors < Minitest::Test
  def test_protocol_error_with_code_and_data
    err = AcpClient::ProtocolError.new("Something went wrong", code: -32600, data: {foo: "bar"})

    assert_equal "Something went wrong", err.message
    assert_equal(-32600, err.code)
    assert_equal({foo: "bar"}, err.data)
  end

  def test_protocol_error_inherits_from_acp_error
    assert_kind_of AcpClient::Error, AcpClient::ProtocolError.new("test")
  end

  def test_connection_error_inherits_from_acp_error
    assert_kind_of AcpClient::Error, AcpClient::ConnectionError.new
  end

  def test_session_error_inherits_from_acp_error
    assert_kind_of AcpClient::Error, AcpClient::SessionError.new
  end
end
