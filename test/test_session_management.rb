# frozen_string_literal: true

require "test_helper"

class TestSessionManagement < Minitest::Test
  def setup
    @pm = MockProcessManager.new
    @pm.start
    @rpc = AcpClient::JsonRpc.new
  end

  def teardown
    @pm.close
  end

  def test_connect_with_load_session_id_sends_session_load_when_capability
    handler = AcpClient::ResponseHandler.new(
      process_manager: @pm,
      json_rpc: @rpc,
      load_session_id: "sess_existing",
      cwd: "/home",
      mcp_servers: []
    )
    handler.start_threads

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 0,
      "result" => {
        "protocolVersion" => 1,
        "agentCapabilities" => {"loadSession" => true}
      }
    }.to_json)

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 2,
      "result" => nil
    }.to_json)

    handler.wait_for_ready

    assert_equal "sess_existing", handler.session_id
    assert handler.initialized
    assert_equal 1, @pm.messages_sent.size, "handler sends session/load after init response"
    load_msg = @pm.messages_sent[0]
    assert_equal "session/load", load_msg[:method]
    assert_equal "sess_existing", load_msg[:params][:sessionId]
    assert_equal "/home", load_msg[:params][:cwd]
  end

  def test_connect_with_load_session_id_sends_session_new_when_no_capability
    handler = AcpClient::ResponseHandler.new(
      process_manager: @pm,
      json_rpc: @rpc,
      load_session_id: "sess_existing"
    )
    handler.start_threads

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 0,
      "result" => {
        "protocolVersion" => 1,
        "agentCapabilities" => {}
      }
    }.to_json)

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {"sessionId" => "sess_new123"}
    }.to_json)

    handler.wait_for_ready

    assert_equal "sess_new123", handler.session_id
    assert_equal "session/new", @pm.messages_sent[0][:method]
  end

  def test_connect_create_session_false_does_not_send_session_new
    handler = AcpClient::ResponseHandler.new(
      process_manager: @pm,
      json_rpc: @rpc,
      create_session: false
    )
    handler.start_threads

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 0,
      "result" => {
        "protocolVersion" => 1,
        "agentCapabilities" => {}
      }
    }.to_json)

    handler.wait_for_ready

    assert_nil handler.session_id
    assert handler.initialized
    assert_equal 0, @pm.messages_sent.size, "handler sends nothing when create_session false"
  end

  def test_list_sessions_pending_request
    handler = AcpClient::ResponseHandler.new(
      process_manager: @pm,
      json_rpc: @rpc,
      create_session: false
    )
    handler.start_threads

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 0,
      "result" => {
        "protocolVersion" => 1,
        "agentCapabilities" => {"sessionCapabilities" => {"list" => true}}
      }
    }.to_json)
    handler.wait_for_ready

    request_id = @rpc.next_id
    handler.register_pending_request(request_id)

    msg = @rpc.session_list_message(request_id: request_id, cwd: "/tmp")
    @pm.send_message(msg)

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => request_id,
      "result" => {
        "sessions" => [{"id" => "s1", "title" => "Session 1"}],
        "nextCursor" => "cursor2"
      }
    }.to_json)

    result = handler.wait_for_pending_response(request_id)
    assert_equal [{"id" => "s1", "title" => "Session 1"}], result["sessions"]
    assert_equal "cursor2", result["nextCursor"]
  end

  def test_load_session_after_create_session_false
    handler = AcpClient::ResponseHandler.new(
      process_manager: @pm,
      json_rpc: @rpc,
      create_session: false
    )
    handler.start_threads

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 0,
      "result" => {
        "protocolVersion" => 1,
        "agentCapabilities" => {"loadSession" => true}
      }
    }.to_json)
    handler.wait_for_ready

    request_id = @rpc.next_id
    handler.register_session_load(request_id, "sess_to_load")

    msg = @rpc.session_load_message(
      request_id: request_id,
      session_id: "sess_to_load",
      cwd: Dir.pwd,
      mcp_servers: []
    )
    @pm.send_message(msg)

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => request_id,
      "result" => nil
    }.to_json)

    handler.wait_for_session

    assert_equal "sess_to_load", handler.session_id
  end

  def test_session_load_error_raises
    handler = AcpClient::ResponseHandler.new(
      process_manager: @pm,
      json_rpc: @rpc,
      load_session_id: "sess_missing"
    )
    handler.start_threads

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 0,
      "result" => {
        "protocolVersion" => 1,
        "agentCapabilities" => {"loadSession" => true}
      }
    }.to_json)

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 2,
      "error" => {"code" => -32602, "message" => "Session not found"}
    }.to_json)

    assert_raises(AcpClient::ProtocolError) do
      handler.wait_for_ready
    end
  end
end
