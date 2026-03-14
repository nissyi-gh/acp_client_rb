# frozen_string_literal: true

require "test_helper"

class TestTerminalHandlers < Minitest::Test
  def setup
    @pm = MockProcessManager.new
    @pm.start
    @rpc = AcpClient::JsonRpc.new
    @terminal_manager = AcpClient::TerminalManager.new
    @handler = AcpClient::ResponseHandler.new(
      process_manager: @pm,
      json_rpc: @rpc,
      terminal_manager: @terminal_manager
    )
  end

  def teardown
    @pm.close
  end

  def test_terminal_create_returns_terminal_id
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 20,
      "method" => "terminal/create",
      "params" => {
        "sessionId" => "sess_test123",
        "command" => "echo",
        "args" => ["hello"]
      }
    }.to_json)

    sleep 0.2
    resp = @pm.messages_sent.find { |m| m[:id] == 20 }
    assert resp, "Expected response for request id 20"
    assert resp[:result][:terminalId].start_with?("term_")
  end

  def test_terminal_output_returns_output
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 21,
      "method" => "terminal/create",
      "params" => {
        "sessionId" => "sess_test123",
        "command" => "echo",
        "args" => ["hello world"]
      }
    }.to_json)

    sleep 0.3
    create_resp = @pm.messages_sent.find { |m| m[:id] == 21 }
    terminal_id = create_resp[:result][:terminalId]

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 22,
      "method" => "terminal/output",
      "params" => {
        "sessionId" => "sess_test123",
        "terminalId" => terminal_id
      }
    }.to_json)

    sleep 0.2
    output_resp = @pm.messages_sent.find { |m| m[:id] == 22 }
    assert output_resp, "Expected response for request id 22"
    assert_includes output_resp[:result][:output], "hello world"
  end

  def test_terminal_release
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 23,
      "method" => "terminal/create",
      "params" => {
        "sessionId" => "sess_test123",
        "command" => "echo",
        "args" => ["x"]
      }
    }.to_json)

    sleep 0.2
    create_resp = @pm.messages_sent.find { |m| m[:id] == 23 }
    terminal_id = create_resp[:result][:terminalId]

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 24,
      "method" => "terminal/release",
      "params" => {
        "sessionId" => "sess_test123",
        "terminalId" => terminal_id
      }
    }.to_json)

    sleep 0.1
    release_resp = @pm.messages_sent.find { |m| m[:id] == 24 }
    assert release_resp, "Expected response for request id 24"
    assert_nil release_resp[:result]
  end

  private

  def init_and_session_flow(pm)
    pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 0, "result" => {"protocolVersion" => 1, "agentCapabilities" => {}}}.to_json)
    pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 1, "result" => {"sessionId" => "sess_test123"}}.to_json)
  end
end
