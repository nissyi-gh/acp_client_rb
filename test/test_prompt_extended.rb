# frozen_string_literal: true

require "test_helper"

class TestPromptExtended < Minitest::Test
  def setup
    @pm = MockProcessManager.new
    @pm.start
    @rpc = AcpClient::JsonRpc.new
    @handler = AcpClient::ResponseHandler.new(process_manager: @pm, json_rpc: @rpc)
  end

  def teardown
    @pm.close
  end

  def test_session_prompt_with_extended_content_sent_correctly
    @handler.start_threads
    init_and_session_flow(@pm, prompt_capabilities: {"image" => true, "embeddedContext" => true})
    @handler.wait_for_ready

    prompt = [
      {type: "text", text: "Analyze this"},
      {type: "image", mimeType: "image/png", data: "iVBORw0KGgo="},
      {type: "resource", resource: {uri: "file:///tmp/x.py", mimeType: "text/x-python", text: "print(1)"}}
    ]

    request_id = @rpc.next_id
    @handler.register_prompt(request_id, "sess_test123")
    msg = @rpc.session_prompt_message(request_id: request_id, session_id: "sess_test123", prompt: prompt)
    @pm.send_message(msg)

    prompt_sent = @pm.messages_sent.find { |m| m[:method] == "session/prompt" }
    assert prompt_sent, "Expected session/prompt message"
    assert_equal 3, prompt_sent[:params][:prompt].size
    assert_equal "image", prompt_sent[:params][:prompt][1][:type]
    assert_equal "resource", prompt_sent[:params][:prompt][2][:type]
  end

  private

  def init_and_session_flow(pm, prompt_capabilities: {})
    pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 0,
      "result" => {
        "protocolVersion" => 1,
        "agentCapabilities" => {"promptCapabilities" => prompt_capabilities}
      }
    }.to_json)
    pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 1, "result" => {"sessionId" => "sess_test123"}}.to_json)
  end
end
