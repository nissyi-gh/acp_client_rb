# frozen_string_literal: true

require "test_helper"

class TestJsonRpc < Minitest::Test
  def setup
    @rpc = AcpClient::JsonRpc.new
  end

  def test_initialize_message
    msg = @rpc.initialize_message

    assert_equal "2.0", msg[:jsonrpc]
    assert_equal 0, msg[:id]
    assert_equal "initialize", msg[:method]
    assert_equal 1, msg[:params][:protocolVersion]
    assert_equal true, msg[:params][:clientCapabilities][:fs][:readTextFile]
    assert_equal true, msg[:params][:clientCapabilities][:fs][:writeTextFile]
    assert_equal true, msg[:params][:clientCapabilities][:terminal]
    assert_equal "ruby-acp-client", msg[:params][:clientInfo][:name]
  end

  def test_initialize_message_custom_client_capabilities
    msg = @rpc.initialize_message(
      client_capabilities: {fs: {readTextFile: false}, terminal: false}
    )
    assert_equal false, msg[:params][:clientCapabilities][:fs][:readTextFile]
    assert_equal true, msg[:params][:clientCapabilities][:fs][:writeTextFile]
    assert_equal false, msg[:params][:clientCapabilities][:terminal]
  end

  def test_initialize_message_custom_client_info
    msg = @rpc.initialize_message(
      client_info: {name: "my-app", title: "My App", version: "2.0.0"}
    )
    assert_equal "my-app", msg[:params][:clientInfo][:name]
    assert_equal "My App", msg[:params][:clientInfo][:title]
    assert_equal "2.0.0", msg[:params][:clientInfo][:version]
  end

  def test_session_new_message
    msg = @rpc.session_new_message(cwd: "/tmp", mcp_servers: [])

    assert_equal "2.0", msg[:jsonrpc]
    assert_equal 1, msg[:id]
    assert_equal "session/new", msg[:method]
    assert_equal "/tmp", msg[:params][:cwd]
    assert_equal [], msg[:params][:mcpServers]
  end

  def test_session_prompt_message
    msg = @rpc.session_prompt_message(
      request_id: 42,
      session_id: "sess_abc",
      prompt: [{type: "text", text: "Hello"}]
    )

    assert_equal "2.0", msg[:jsonrpc]
    assert_equal 42, msg[:id]
    assert_equal "session/prompt", msg[:method]
    assert_equal "sess_abc", msg[:params][:sessionId]
    assert_equal [{type: "text", text: "Hello"}], msg[:params][:prompt]
  end

  def test_session_prompt_message_extended_content
    prompt = [
      {type: "text", text: "Analyze this image"},
      {type: "image", mimeType: "image/png", data: "iVBORw0KGgo="},
      {type: "resource", resource: {uri: "file:///tmp/code.py", mimeType: "text/x-python", text: "print(1)"}}
    ]
    msg = @rpc.session_prompt_message(request_id: 43, session_id: "sess_xyz", prompt: prompt)

    assert_equal "session/prompt", msg[:method]
    assert_equal 3, msg[:params][:prompt].size
    assert_equal "image", msg[:params][:prompt][1][:type]
    assert_equal "image/png", msg[:params][:prompt][1][:mimeType]
    assert_equal "resource", msg[:params][:prompt][2][:type]
    assert_equal "file:///tmp/code.py", msg[:params][:prompt][2][:resource][:uri]
  end

  def test_session_cancel_message
    msg = @rpc.session_cancel_message(session_id: "sess_xyz")

    assert_equal "2.0", msg[:jsonrpc]
    assert_nil msg[:id]
    assert_equal "session/cancel", msg[:method]
    assert_equal "sess_xyz", msg[:params][:sessionId]
  end

  def test_session_load_message
    msg = @rpc.session_load_message(request_id: 5, session_id: "sess_load1", cwd: "/home", mcp_servers: [])

    assert_equal "2.0", msg[:jsonrpc]
    assert_equal 5, msg[:id]
    assert_equal "session/load", msg[:method]
    assert_equal "sess_load1", msg[:params][:sessionId]
    assert_equal "/home", msg[:params][:cwd]
    assert_equal [], msg[:params][:mcpServers]
  end

  def test_session_list_message
    msg = @rpc.session_list_message(request_id: 6, cwd: "/tmp", cursor: "next123")

    assert_equal "2.0", msg[:jsonrpc]
    assert_equal 6, msg[:id]
    assert_equal "session/list", msg[:method]
    assert_equal "/tmp", msg[:params][:cwd]
    assert_equal "next123", msg[:params][:cursor]
  end

  def test_session_list_message_empty_params
    msg = @rpc.session_list_message(request_id: 7)

    assert_equal "session/list", msg[:method]
    assert_equal({}, msg[:params])
  end

  def test_next_id_increments
    assert_equal 2, @rpc.next_id
    assert_equal 3, @rpc.next_id
    assert_equal 4, @rpc.next_id
  end
end
