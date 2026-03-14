# frozen_string_literal: true

require "test_helper"

class TestRequestPermission < Minitest::Test
  def setup
    @pm = MockProcessManager.new
    @pm.start
    @rpc = AcpClient::JsonRpc.new
    @handler = AcpClient::ResponseHandler.new(process_manager: @pm, json_rpc: @rpc)
  end

  def teardown
    @pm.close
  end

  def test_request_permission_default_allows
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 30,
      "method" => "session/request_permission",
      "params" => {
        "sessionId" => "sess_test123",
        "toolCall" => {"toolCallId" => "call_001"},
        "options" => [
          {"optionId" => "allow-once", "name" => "Allow once", "kind" => "allow_once"},
          {"optionId" => "reject-once", "name" => "Reject", "kind" => "reject_once"}
        ]
      }
    }.to_json)

    sleep 0.1
    resp = @pm.messages_sent.find { |m| m[:id] == 30 }
    assert resp, "Expected response for request id 30"
    assert_equal "selected", resp[:result][:outcome][:outcome]
    assert_equal "allow-once", resp[:result][:outcome][:optionId]
  end

  def test_request_permission_custom_callback
    @handler.on_permission_request do |session_id, tool_call, options, cancelled|
      assert_equal "sess_test123", session_id
      assert_equal "call_002", tool_call["toolCallId"]
      assert_equal 2, options.size
      {outcome: "selected", optionId: "reject-once"}
    end
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 31,
      "method" => "session/request_permission",
      "params" => {
        "sessionId" => "sess_test123",
        "toolCall" => {"toolCallId" => "call_002"},
        "options" => [
          {"optionId" => "allow-once", "name" => "Allow", "kind" => "allow_once"},
          {"optionId" => "reject-once", "name" => "Reject", "kind" => "reject_once"}
        ]
      }
    }.to_json)

    sleep 0.1
    resp = @pm.messages_sent.find { |m| m[:id] == 31 }
    assert resp, "Expected response for request id 31"
    assert_equal "selected", resp[:result][:outcome][:outcome]
    assert_equal "reject-once", resp[:result][:outcome][:optionId]
  end

  def test_cancel_pending_permission
    @handler.on_permission_request do |_session_id, _tool_call, _options, cancelled|
      sleep 0.01 while !cancelled.call
      {outcome: "cancelled"}
    end
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 32,
      "method" => "session/request_permission",
      "params" => {
        "sessionId" => "sess_test123",
        "toolCall" => {"toolCallId" => "call_003"},
        "options" => [{"optionId" => "allow-once", "name" => "Allow", "kind" => "allow_once"}]
      }
    }.to_json)

    sleep 0.05
    @handler.cancel_pending_permission
    sleep 0.15

    resp = @pm.messages_sent.find { |m| m[:id] == 32 }
    assert resp, "Expected response for request id 32"
    assert_equal "cancelled", resp[:result][:outcome][:outcome]
    assert_nil resp[:result][:outcome][:optionId]
  end

  private

  def init_and_session_flow(pm)
    pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 0, "result" => {"protocolVersion" => 1, "agentCapabilities" => {}}}.to_json)
    pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 1, "result" => {"sessionId" => "sess_test123"}}.to_json)
  end
end
