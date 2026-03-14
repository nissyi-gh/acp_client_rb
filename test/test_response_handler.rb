# frozen_string_literal: true

require "test_helper"

class TestResponseHandler < Minitest::Test
  def setup
    @pm = MockProcessManager.new
    @pm.start
    @rpc = AcpClient::JsonRpc.new
    @handler = AcpClient::ResponseHandler.new(process_manager: @pm, json_rpc: @rpc)
  end

  def teardown
    @pm.close
  end

  def test_handle_initialize_and_session_new
    @handler.start_threads

    init_response = {
      "jsonrpc" => "2.0",
      "id" => 0,
      "result" => {
        "protocolVersion" => 1,
        "agentCapabilities" => {"loadSession" => true}
      }
    }
    @pm.inject_stdout_line(init_response.to_json)

    session_response = {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {"sessionId" => "sess_test123"}
    }
    @pm.inject_stdout_line(session_response.to_json)

    @handler.wait_for_ready

    assert_equal "sess_test123", @handler.session_id
    assert @handler.initialized
    assert_equal({"loadSession" => true}, @handler.agent_capabilities)
    assert_equal 1, @pm.messages_sent.size, "handler sends session/new after init response"
    assert_equal "session/new", @pm.messages_sent[0][:method]
  end

  def test_agent_message_chunk_callback
    chunks = []
    @handler.on_text_chunk { |t| chunks << t }
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "method" => "session/update",
      "params" => {
        "sessionId" => "sess_test123",
        "update" => {
          "sessionUpdate" => "agent_message_chunk",
          "content" => {"type" => "text", "text" => "Hello "}
        }
      }
    }.to_json)
    @pm.inject_stdout_line({
      "method" => "session/update",
      "params" => {
        "sessionId" => "sess_test123",
        "update" => {
          "sessionUpdate" => "agent_message_chunk",
          "content" => {"type" => "text", "text" => "World"}
        }
      }
    }.to_json)

    sleep 0.1
    assert_equal ["Hello ", "World"], chunks
  end

  def test_initialize_error_raises_protocol_error
    @handler.start_threads

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 0,
      "error" => {"code" => -32600, "message" => "Invalid request"}
    }.to_json)

    assert_raises(AcpClient::ProtocolError) do
      @handler.wait_for_ready
    end
  end

  private

  def init_and_session_flow(pm)
    pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 0, "result" => {"protocolVersion" => 1, "agentCapabilities" => {}}}.to_json)
    pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 1, "result" => {"sessionId" => "sess_test123"}}.to_json)
  end
end
