# frozen_string_literal: true

require "test_helper"

class TestConfigFlexibility < Minitest::Test
  def setup
    @pm = MockProcessManager.new
    @pm.start
  end

  def teardown
    @pm.close
  end

  def test_process_manager_custom_command
    pm = AcpClient::ProcessManager.new(command: "sleep 2")
    pm.start
    assert pm.running?
    pm.shutdown
  end

  def test_process_manager_custom_env
    pm = AcpClient::ProcessManager.new(command: "sleep 2", env: {"ACP_TEST_VAR" => "test_value"})
    pm.start
    assert pm.running?
    pm.shutdown
  end

  def test_client_sends_custom_client_capabilities
    client = AcpClient::Client.new(
      process_manager: @pm,
      client_capabilities: {fs: {readTextFile: false}, terminal: false}
    )
    Thread.new do
      sleep 0.1
      @pm.inject_stdout_line({
        "jsonrpc" => "2.0",
        "id" => 0,
        "result" => {"protocolVersion" => 1, "agentCapabilities" => {}}
      }.to_json)
      @pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 1, "result" => {"sessionId" => "sess_abc"}}.to_json)
    end
    client.connect

    init_msg = @pm.messages_sent.find { |m| m[:method] == "initialize" }
    assert init_msg, "Expected initialize message"
    assert_equal false, init_msg[:params][:clientCapabilities][:fs][:readTextFile]
    assert_equal false, init_msg[:params][:clientCapabilities][:terminal]
  end

  def test_client_sends_custom_client_info
    client = AcpClient::Client.new(
      process_manager: @pm,
      client_info: {name: "custom-client", title: "Custom", version: "9.9.9"}
    )
    Thread.new do
      sleep 0.1
      @pm.inject_stdout_line({
        "jsonrpc" => "2.0",
        "id" => 0,
        "result" => {"protocolVersion" => 1, "agentCapabilities" => {}}
      }.to_json)
      @pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 1, "result" => {"sessionId" => "sess_xyz"}}.to_json)
    end
    client.connect

    init_msg = @pm.messages_sent.find { |m| m[:method] == "initialize" }
    assert init_msg, "Expected initialize message"
    assert_equal "custom-client", init_msg[:params][:clientInfo][:name]
    assert_equal "Custom", init_msg[:params][:clientInfo][:title]
    assert_equal "9.9.9", init_msg[:params][:clientInfo][:version]
  end
end
