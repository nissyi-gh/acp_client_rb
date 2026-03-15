# frozen_string_literal: true

require "json"

module AcpClient
  class JsonRpc
    JSON_RPC_VERSION = "2.0"
    INITIALIZE_ID = 0
    SESSION_NEW_ID = 1
    PROMPT_START_ID = 2

    def initialize
      @next_id = PROMPT_START_ID
    end

    def next_id
      id = @next_id
      @next_id += 1
      id
    end

    def initialize_message
      {
        jsonrpc: JSON_RPC_VERSION,
        id: INITIALIZE_ID,
        method: "initialize",
        params: {
          protocolVersion: 1,
          clientCapabilities: {
            fs: {readTextFile: true, writeTextFile: true},
            terminal: true
          },
          clientInfo: {
            name: "ruby-acp-client",
            title: "Ruby ACP Client",
            version: AcpClient::VERSION
          }
        }
      }
    end

    def session_new_message(cwd: Dir.pwd, mcp_servers: [])
      {
        jsonrpc: JSON_RPC_VERSION,
        id: SESSION_NEW_ID,
        method: "session/new",
        params: {
          cwd: cwd,
          mcpServers: mcp_servers
        }
      }
    end

    # @param prompt [Array<Hash>] ContentBlock array (e.g. [{type: "text", text: "..."}], [{type: "image", mimeType: "image/png", data: "..."}])
    def session_prompt_message(request_id:, session_id:, prompt:)
      {
        jsonrpc: JSON_RPC_VERSION,
        id: request_id,
        method: "session/prompt",
        params: {
          sessionId: session_id,
          prompt: prompt
        }
      }
    end

    def session_cancel_message(session_id:)
      {
        jsonrpc: JSON_RPC_VERSION,
        method: "session/cancel",
        params: {
          sessionId: session_id
        }
      }
    end

    def session_load_message(request_id:, session_id:, cwd: Dir.pwd, mcp_servers: [])
      {
        jsonrpc: JSON_RPC_VERSION,
        id: request_id,
        method: "session/load",
        params: {
          sessionId: session_id,
          cwd: cwd,
          mcpServers: mcp_servers
        }
      }
    end

    def session_list_message(request_id:, cwd: nil, cursor: nil)
      params = {}
      params[:cwd] = cwd if cwd
      params[:cursor] = cursor if cursor
      {
        jsonrpc: JSON_RPC_VERSION,
        id: request_id,
        method: "session/list",
        params: params
      }
    end

    def generate(id:, method:, params:)
      {
        jsonrpc: JSON_RPC_VERSION,
        id: id,
        method: method,
        params: params
      }
    end
  end
end
