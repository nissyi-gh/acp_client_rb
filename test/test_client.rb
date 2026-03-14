# frozen_string_literal: true

require "test_helper"

class TestClient < Minitest::Test
  def test_new_returns_client_instance
    client = AcpClient.new
    assert_kind_of AcpClient::Client, client
  end

  def test_client_has_json_rpc_and_process_manager
    client = AcpClient::Client.new
    assert_kind_of AcpClient::JsonRpc, client.json_rpc
    assert_kind_of AcpClient::ProcessManager, client.process_manager
  end

  def test_agent_capabilities_before_connect_returns_empty_hash
    client = AcpClient::Client.new
    assert_equal({}, client.agent_capabilities)
  end

  def test_agent_capabilities_after_shutdown_returns_empty_hash
    client = AcpClient::Client.new
    client.shutdown
    assert_equal({}, client.agent_capabilities)
  end
end
