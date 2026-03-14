# frozen_string_literal: true

require "test_helper"

class TestSessionUpdate < Minitest::Test
  def setup
    @pm = MockProcessManager.new
    @pm.start
    @rpc = AcpClient::JsonRpc.new
    @handler = AcpClient::ResponseHandler.new(process_manager: @pm, json_rpc: @rpc)
  end

  def teardown
    @pm.close
  end

  def test_plan_callback
    plans = []
    @handler.on_plan { |sid, entries| plans << [sid, entries] }
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "method" => "session/update",
      "params" => {
        "sessionId" => "sess_test123",
        "update" => {
          "sessionUpdate" => "plan",
          "entries" => [
            {"content" => "Step 1", "priority" => "high", "status" => "pending"},
            {"content" => "Step 2", "priority" => "low", "status" => "pending"}
          ]
        }
      }
    }.to_json)

    sleep 0.1
    assert_equal 1, plans.size
    assert_equal "sess_test123", plans[0][0]
    assert_equal 2, plans[0][1].size
    assert_equal "Step 1", plans[0][1][0]["content"]
  end

  def test_tool_call_callback
    tool_calls = []
    @handler.on_tool_call { |sid, data| tool_calls << [sid, data] }
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "method" => "session/update",
      "params" => {
        "sessionId" => "sess_test123",
        "update" => {
          "sessionUpdate" => "tool_call",
          "toolCallId" => "call_001",
          "title" => "Running tests",
          "kind" => "execute",
          "status" => "pending"
        }
      }
    }.to_json)

    sleep 0.1
    assert_equal 1, tool_calls.size
    assert_equal "sess_test123", tool_calls[0][0]
    assert_equal "call_001", tool_calls[0][1][:tool_call_id]
    assert_equal "Running tests", tool_calls[0][1][:title]
    assert_equal "execute", tool_calls[0][1][:kind]
  end

  def test_tool_call_update_callback
    updates = []
    @handler.on_tool_call_update { |sid, data| updates << [sid, data] }
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "method" => "session/update",
      "params" => {
        "sessionId" => "sess_test123",
        "update" => {
          "sessionUpdate" => "tool_call_update",
          "toolCallId" => "call_001",
          "status" => "completed",
          "content" => [{"type" => "content", "content" => {"type" => "text", "text" => "Done"}}]
        }
      }
    }.to_json)

    sleep 0.1
    assert_equal 1, updates.size
    assert_equal "completed", updates[0][1][:status]
    assert_equal 1, updates[0][1][:content].size
  end

  def test_session_info_update_callback
    infos = []
    @handler.on_session_info_update { |sid, data| infos << [sid, data] }
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "method" => "session/update",
      "params" => {
        "sessionId" => "sess_test123",
        "update" => {
          "sessionUpdate" => "session_info_update",
          "title" => "New session title"
        }
      }
    }.to_json)

    sleep 0.1
    assert_equal 1, infos.size
    assert_equal "New session title", infos[0][1][:title]
  end

  def test_user_message_chunk_callback
    chunks = []
    @handler.on_user_message_chunk { |sid, content| chunks << [sid, content] }
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "method" => "session/update",
      "params" => {
        "sessionId" => "sess_test123",
        "update" => {
          "sessionUpdate" => "user_message_chunk",
          "content" => {"type" => "text", "text" => "User said this"}
        }
      }
    }.to_json)

    sleep 0.1
    assert_equal 1, chunks.size
    assert_equal "User said this", chunks[0][1]["text"]
  end

  private

  def init_and_session_flow(pm)
    pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 0, "result" => {"protocolVersion" => 1, "agentCapabilities" => {}}}.to_json)
    pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 1, "result" => {"sessionId" => "sess_test123"}}.to_json)
  end
end
