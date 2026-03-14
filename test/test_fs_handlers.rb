# frozen_string_literal: true

require "test_helper"
require "tempfile"

class TestFsHandlers < Minitest::Test
  def setup
    @pm = MockProcessManager.new
    @pm.start
    @rpc = AcpClient::JsonRpc.new
    @handler = AcpClient::ResponseHandler.new(process_manager: @pm, json_rpc: @rpc)
  end

  def teardown
    @pm.close
  end

  def test_fs_read_text_file_default
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    tmp = Tempfile.new("acp_test")
    tmp.write("line1\nline2\nline3\nline4\nline5")
    tmp.close

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 10,
      "method" => "fs/read_text_file",
      "params" => {
        "sessionId" => "sess_test123",
        "path" => tmp.path
      }
    }.to_json)

    sleep 0.1
    assert_operator @pm.messages_sent.size, :>=, 1
    resp = @pm.messages_sent.find { |m| m[:id] == 10 }
    assert resp, "Expected response for request id 10"
    assert_equal "line1\nline2\nline3\nline4\nline5", resp[:result][:content]

    tmp.unlink
  end

  def test_fs_read_text_file_with_line_and_limit
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    tmp = Tempfile.new("acp_test")
    tmp.write("line1\nline2\nline3\nline4\nline5")
    tmp.close

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 11,
      "method" => "fs/read_text_file",
      "params" => {
        "sessionId" => "sess_test123",
        "path" => tmp.path,
        "line" => 2,
        "limit" => 2
      }
    }.to_json)

    sleep 0.1
    resp = @pm.messages_sent.find { |m| m[:id] == 11 }
    assert resp, "Expected response for request id 11"
    assert_equal "line2\nline3\n", resp[:result][:content]

    tmp.unlink
  end

  def test_fs_write_text_file_default
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    tmp = Tempfile.new("acp_test")
    path = tmp.path
    tmp.close
    tmp.unlink

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 12,
      "method" => "fs/write_text_file",
      "params" => {
        "sessionId" => "sess_test123",
        "path" => path,
        "content" => "hello world"
      }
    }.to_json)

    sleep 0.1
    resp = @pm.messages_sent.find { |m| m[:id] == 12 }
    assert resp, "Expected response for request id 12"
    assert_nil resp[:result]
    assert_equal "hello world", File.read(path)

    File.unlink(path)
  end

  def test_fs_read_text_file_custom_handler
    read_content = nil
    @handler.on_fs_read_text_file do |path, line, limit|
      read_content = [path, line, limit]
      "custom content"
    end
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 13,
      "method" => "fs/read_text_file",
      "params" => {
        "sessionId" => "sess_test123",
        "path" => "/tmp/foo",
        "line" => 5,
        "limit" => 10
      }
    }.to_json)

    sleep 0.1
    assert_equal ["/tmp/foo", 5, 10], read_content
    resp = @pm.messages_sent.find { |m| m[:id] == 13 }
    assert resp, "Expected response for request id 13"
    assert_equal "custom content", resp[:result][:content]
  end

  def test_unknown_method_returns_error
    @handler.start_threads

    init_and_session_flow(@pm)
    @handler.wait_for_ready

    @pm.inject_stdout_line({
      "jsonrpc" => "2.0",
      "id" => 99,
      "method" => "unknown/method",
      "params" => {}
    }.to_json)

    sleep 0.1
    resp = @pm.messages_sent.find { |m| m[:id] == 99 }
    assert resp, "Expected error response for request id 99"
    assert resp[:error]
    assert_equal(-32601, resp[:error][:code])
    assert_includes resp[:error][:message], "Method not found"
  end

  private

  def init_and_session_flow(pm)
    pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 0, "result" => {"protocolVersion" => 1, "agentCapabilities" => {}}}.to_json)
    pm.inject_stdout_line({"jsonrpc" => "2.0", "id" => 1, "result" => {"sessionId" => "sess_test123"}}.to_json)
  end
end
