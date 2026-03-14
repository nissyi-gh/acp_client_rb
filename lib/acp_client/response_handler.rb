# frozen_string_literal: true

require "json"

module AcpClient
  class ResponseHandler
    attr_reader :session_id, :initialized, :agent_capabilities

    def initialize(process_manager:, json_rpc:, terminal_manager: nil, load_session_id: nil, create_session: true, cwd: Dir.pwd, mcp_servers: [])
      @process_manager = process_manager
      @json_rpc = json_rpc
      @terminal_manager = terminal_manager || TerminalManager.new
      @load_session_id = load_session_id
      @create_session = create_session
      @cwd = cwd
      @mcp_servers = mcp_servers

      @mutex = Mutex.new
      @ready = ConditionVariable.new
      @session_ready_cv = ConditionVariable.new
      @turn_done = ConditionVariable.new

      @session_id = nil
      @initialized = false
      @session_ready = false
      @agent_capabilities = {}
      @fatal_error = nil
      @session_load_request_id = nil

      @buffers = Hash.new { |h, sid| h[sid] = MessageBuffer.new }
      @available_commands_by_session = {}

      @prompt_session_by_request_id = {}
      @active_turn_request_id = nil
      @error_by_request_id = {}
      @pending_requests = {}

      @reader_thread = nil
      @stderr_thread = nil
      @on_text_chunk = nil
      @on_fs_read_text_file = nil
      @on_fs_write_text_file = nil
      @on_plan = nil
      @on_tool_call = nil
      @on_tool_call_update = nil
      @on_session_info_update = nil
      @on_current_mode_update = nil
      @on_user_message_chunk = nil
      @on_permission_request = nil
      @pending_permission = nil
      @permission_cancelled = false
    end

    def on_permission_request(&block)
      @on_permission_request = block
    end

    def cancel_pending_permission
      @mutex.synchronize do
        return unless @pending_permission && !@pending_permission[:responded]

        @permission_cancelled = true
        send_permission_response(@pending_permission[:id], {outcome: "cancelled"})
        @pending_permission[:responded] = true
        @pending_permission = nil
      end
    end

    def on_text_chunk(&block)
      @on_text_chunk = block
    end

    def on_fs_read_text_file(&block)
      @on_fs_read_text_file = block
    end

    def on_fs_write_text_file(&block)
      @on_fs_write_text_file = block
    end

    def on_plan(&block)
      @on_plan = block
    end

    def on_tool_call(&block)
      @on_tool_call = block
    end

    def on_tool_call_update(&block)
      @on_tool_call_update = block
    end

    def on_session_info_update(&block)
      @on_session_info_update = block
    end

    def on_current_mode_update(&block)
      @on_current_mode_update = block
    end

    def on_user_message_chunk(&block)
      @on_user_message_chunk = block
    end

    def start_threads
      start_stderr_thread
      start_reader_thread
    end

    def stop_threads
      begin
        @reader_thread&.kill
      rescue
        nil
      end
      begin
        @stderr_thread&.kill
      rescue
        nil
      end
    end

    def wait_for_ready
      @mutex.synchronize do
        @ready.wait(@mutex) until @initialized || @fatal_error
        raise @fatal_error if @fatal_error
      end
    end

    def wait_for_session
      @mutex.synchronize do
        @session_ready_cv.wait(@mutex) until @session_ready || @fatal_error
        raise @fatal_error if @fatal_error
      end
    end

    def wait_for_turn_completion(request_id)
      @mutex.synchronize do
        @turn_done.wait(@mutex) while @active_turn_request_id == request_id
        if (err = @error_by_request_id.delete(request_id))
          raise err
        end
      end
    end

    def register_prompt(request_id, session_id)
      @mutex.synchronize do
        @prompt_session_by_request_id[request_id] = session_id
        @active_turn_request_id = request_id
        @buffers[session_id].clear
      end
    end

    def current_session_id
      @mutex.synchronize { @session_id }
    end

    def register_pending_request(request_id)
      @mutex.synchronize do
        @pending_requests[request_id] = {result: nil, error: nil, cond: ConditionVariable.new}
      end
    end

    def wait_for_pending_response(request_id)
      @mutex.synchronize do
        pr = @pending_requests[request_id]
        raise ArgumentError, "Request #{request_id} not registered" unless pr
        pr[:cond].wait(@mutex) until pr[:result] || pr[:error]
        result = pr[:result]
        error = pr[:error]
        @pending_requests.delete(request_id)
        raise error if error
        result
      end
    end

    def session_load_request_id
      @mutex.synchronize { @session_load_request_id }
    end

    def register_session_load(request_id, session_id)
      @mutex.synchronize do
        @session_load_request_id = request_id
        @load_session_id = session_id
      end
    end

    private

    def start_stderr_thread
      @stderr_thread = Thread.new do
        @process_manager.stderr.each_line do |line|
          warn "[agent stderr] #{line.chomp}"
        end
      rescue IOError
        # stream closed
      end
    end

    def start_reader_thread
      @reader_thread = Thread.new do
        @process_manager.stdout.each_line do |line|
          line = line.chomp
          next if line.empty?

          begin
            msg = JSON.parse(line)
            handle_message(msg)
          rescue JSON::ParserError => e
            warn "[parse error] #{e.message}: #{line}"
          end
        end
      rescue IOError
        # stream closed
      end
    end

    def handle_message(msg)
      if msg["id"].nil? && msg["method"]
        handle_notification(msg)
      elsif msg["method"] && msg.key?("id") && !msg.key?("result") && !msg.key?("error")
        handle_incoming_request(msg)
      else
        handle_response(msg)
      end
    end

    def handle_incoming_request(msg)
      id = msg["id"]
      method_name = msg["method"]
      params = msg["params"] || {}

      case method_name
      when "fs/read_text_file"
        handle_fs_read_text_file(id, params)
      when "fs/write_text_file"
        handle_fs_write_text_file(id, params)
      when "terminal/create"
        handle_terminal_create(id, params)
      when "terminal/output"
        handle_terminal_output(id, params)
      when "terminal/wait_for_exit"
        handle_terminal_wait_for_exit(id, params)
      when "terminal/kill"
        handle_terminal_kill(id, params)
      when "terminal/release"
        handle_terminal_release(id, params)
      when "session/request_permission"
        handle_request_permission(id, params)
      else
        send_error_response(id, -32601, "Method not found: #{method_name}")
      end
    end

    def handle_fs_read_text_file(id, params)
      path = params["path"]
      line = params["line"]
      limit = params["limit"]

      content = if @on_fs_read_text_file
        @on_fs_read_text_file.call(path, line, limit)
      else
        default_fs_read_text_file(path, line, limit)
      end

      send_response(id, {content: content})
    rescue Errno::ENOENT => e
      send_error_response(id, -32000, "File not found: #{e.message}")
    rescue => e
      send_error_response(id, -32603, "Internal error: #{e.message}")
    end

    def handle_fs_write_text_file(id, params)
      path = params["path"]
      content = params["content"] || ""

      if @on_fs_write_text_file
        @on_fs_write_text_file.call(path, content)
      else
        default_fs_write_text_file(path, content)
      end

      send_response(id, nil)
    rescue => e
      send_error_response(id, -32603, "Internal error: #{e.message}")
    end

    def default_fs_read_text_file(path, line, limit)
      full_content = File.read(path)
      return full_content if line.nil? && limit.nil?

      lines = full_content.lines
      start_idx = line ? [(line - 1), 0].max : 0
      count = limit ? [limit, lines.size - start_idx].min : (lines.size - start_idx)
      lines[start_idx, count]&.join || ""
    end

    def default_fs_write_text_file(path, content)
      File.write(path, content)
    end

    def handle_terminal_create(id, params)
      session_id = params["sessionId"]
      command = params["command"] || "sh"
      args = params["args"] || []
      env = params["env"] || []
      cwd = params["cwd"]
      output_byte_limit = params["outputByteLimit"] || 1_048_576

      terminal_id = @terminal_manager.create(
        session_id: session_id,
        command: command,
        args: args,
        env: env,
        cwd: cwd,
        output_byte_limit: output_byte_limit
      )
      send_response(id, {terminalId: terminal_id})
    rescue => e
      send_error_response(id, -32603, "Internal error: #{e.message}")
    end

    def handle_terminal_output(id, params)
      terminal_id = params["terminalId"]
      result = @terminal_manager.output(terminal_id)
      send_response(id, result)
    rescue ProtocolError => e
      send_error_response(id, -32000, e.message)
    rescue => e
      send_error_response(id, -32603, "Internal error: #{e.message}")
    end

    def handle_terminal_wait_for_exit(id, params)
      terminal_id = params["terminalId"]
      result = @terminal_manager.wait_for_exit(terminal_id)
      send_response(id, result)
    rescue ProtocolError => e
      send_error_response(id, -32000, e.message)
    rescue => e
      send_error_response(id, -32603, "Internal error: #{e.message}")
    end

    def handle_terminal_kill(id, params)
      terminal_id = params["terminalId"]
      @terminal_manager.kill(terminal_id)
      send_response(id, nil)
    rescue ProtocolError => e
      send_error_response(id, -32000, e.message)
    rescue => e
      send_error_response(id, -32603, "Internal error: #{e.message}")
    end

    def handle_terminal_release(id, params)
      terminal_id = params["terminalId"]
      @terminal_manager.release(terminal_id)
      send_response(id, nil)
    rescue ProtocolError => e
      send_error_response(id, -32000, e.message)
    rescue => e
      send_error_response(id, -32603, "Internal error: #{e.message}")
    end

    def send_response(id, result)
      response = {
        jsonrpc: "2.0",
        id: id,
        result: result
      }
      @process_manager.send_message(response)
    end

    def send_error_response(id, code, message)
      response = {
        jsonrpc: "2.0",
        id: id,
        error: {code: code, message: message}
      }
      @process_manager.send_message(response)
    end

    def handle_request_permission(id, params)
      session_id = params["sessionId"]
      tool_call = params["toolCall"] || {}
      options = params["options"] || []

      if @on_permission_request.nil?
        allow_option = options.find { |o| (o["kind"] || o[:kind])&.to_s&.start_with?("allow") }
        option_id = allow_option&.dig("optionId") || allow_option&.dig(:optionId) || options.first&.dig("optionId") || "allow-once"
        send_permission_response(id, {outcome: "selected", optionId: option_id})
        return
      end

      @mutex.synchronize do
        @permission_cancelled = false
        @pending_permission = {id: id, responded: false}
      end

      cancelled_proc = -> { @permission_cancelled }

      outcome = @on_permission_request.call(session_id, tool_call, options, cancelled_proc)

      @mutex.synchronize do
        return if @pending_permission && @pending_permission[:responded]

        send_permission_response(id, outcome)
        @pending_permission[:responded] = true if @pending_permission
        @pending_permission = nil
      end
    rescue => e
      @mutex.synchronize do
        @pending_permission = nil
      end
      send_error_response(id, -32603, "Internal error: #{e.message}")
    end

    def send_permission_response(id, outcome)
      response = {
        jsonrpc: "2.0",
        id: id,
        result: {outcome: outcome}
      }
      @process_manager.send_message(response)
    end

    def handle_notification(msg)
      return unless msg["method"] == "session/update"

      params = msg["params"] || {}
      sid = params["sessionId"]
      upd = params["update"] || {}

      case upd["sessionUpdate"]
      when "available_commands_update"
        @mutex.synchronize do
          @available_commands_by_session[sid] = upd["availableCommands"] || []
        end
      when "agent_message_chunk"
        handle_agent_message_chunk(sid, upd)
      when "plan"
        handle_plan(sid, upd)
      when "tool_call"
        handle_tool_call(sid, upd)
      when "tool_call_update"
        handle_tool_call_update(sid, upd)
      when "session_info_update"
        handle_session_info_update(sid, upd)
      when "current_mode_update"
        handle_current_mode_update(sid, upd)
      when "user_message_chunk"
        handle_user_message_chunk(sid, upd)
      end
    end

    def handle_plan(sid, upd)
      entries = upd["entries"] || []
      @on_plan&.call(sid, entries)
    end

    def handle_tool_call(sid, upd)
      tool_call_id = upd["toolCallId"]
      title = upd["title"]
      kind = upd["kind"]
      status = upd["status"]
      content = upd["content"]
      @on_tool_call&.call(sid, tool_call_id: tool_call_id, title: title, kind: kind, status: status, content: content)
    end

    def handle_tool_call_update(sid, upd)
      tool_call_id = upd["toolCallId"]
      status = upd["status"]
      content = upd["content"]
      @on_tool_call_update&.call(sid, tool_call_id: tool_call_id, status: status, content: content)
    end

    def handle_session_info_update(sid, upd)
      title = upd["title"]
      updated_at = upd["updatedAt"]
      meta = upd["_meta"]
      @on_session_info_update&.call(sid, title: title, updated_at: updated_at, meta: meta)
    end

    def handle_current_mode_update(sid, upd)
      mode = upd["mode"]
      @on_current_mode_update&.call(sid, mode)
    end

    def handle_user_message_chunk(sid, upd)
      content = upd["content"] || {}
      @on_user_message_chunk&.call(sid, content)
    end

    def handle_agent_message_chunk(sid, upd)
      content = upd["content"] || {}
      return unless content["type"] == "text"

      text = content["text"].to_s
      @mutex.synchronize { @buffers[sid].append_text(text) }

      @on_text_chunk&.call(text)
    end

    def handle_response(msg)
      id = msg["id"]

      if id == JsonRpc::INITIALIZE_ID && msg["result"]
        handle_initialize_response(msg["result"])
        return
      end

      if id == JsonRpc::SESSION_NEW_ID && msg["result"]
        handle_session_new_response(msg["result"])
        return
      end

      if id && @mutex.synchronize { id == @session_load_request_id }
        if msg["error"]
          handle_error_response(id, msg["error"], fatal: true)
        else
          handle_session_load_response
        end
        return
      end

      if id && @mutex.synchronize { @pending_requests.key?(id) }
        if msg["error"]
          complete_pending_request(id, nil, protocol_error_from(msg["error"]))
        else
          complete_pending_request(id, msg["result"], nil)
        end
        return
      end

      if msg["result"].is_a?(Hash) && msg["result"].key?("stopReason")
        handle_prompt_response(id, msg["result"])
        return
      end

      if msg["error"]
        handle_error_response(id, msg["error"])
      end
    end

    def protocol_error_from(error)
      code = error["code"]
      message = error["message"] || error.to_s
      data = error["data"]
      ProtocolError.new(message, code: code, data: data)
    end

    def handle_initialize_response(result = nil)
      caps = nil
      @mutex.synchronize do
        @agent_capabilities = (result || {}).fetch("agentCapabilities", {})
        caps = @agent_capabilities
      end
      unless @create_session
        @mutex.synchronize do
          @initialized = true
          @ready.broadcast
        end
        return
      end
      message = if @load_session_id && load_session_capability?(caps)
        req_id = @json_rpc.next_id
        @mutex.synchronize { @session_load_request_id = req_id }
        @json_rpc.session_load_message(
          request_id: req_id,
          session_id: @load_session_id,
          cwd: @cwd,
          mcp_servers: @mcp_servers
        )
      else
        @json_rpc.session_new_message(cwd: @cwd, mcp_servers: @mcp_servers)
      end
      @process_manager.send_message(message)
    end

    def load_session_capability?(caps)
      caps["loadSession"] == true || caps.dig("sessionCapabilities", "loadSession") == true
    end

    def handle_session_new_response(result)
      sid = result["sessionId"] || result["id"] || result["session_id"]
      raise SessionError, "Could not find session id in response: #{result}" unless sid

      @mutex.synchronize do
        @session_id = sid
        @initialized = true
        @session_ready = true
        @ready.broadcast
        @session_ready_cv.broadcast
      end

      puts "\n[info] session_id=#{sid}"
      puts "[info] You can now type messages. Type 'exit' to quit."
    end

    def handle_session_load_response
      @mutex.synchronize do
        @session_id = @load_session_id
        @initialized = true
        @session_ready = true
        @ready.broadcast
        @session_ready_cv.broadcast
      end

      puts "\n[info] session_id=#{@load_session_id} (loaded)"
      puts "[info] You can now type messages. Type 'exit' to quit."
    end

    def complete_pending_request(id, result, error)
      @mutex.synchronize do
        pr = @pending_requests[id]
        if pr
          pr[:result] = result
          pr[:error] = error
          pr[:cond].broadcast
        end
      end
    end

    def handle_prompt_response(id, result)
      stop_reason = result["stopReason"]
      sid = @mutex.synchronize { @prompt_session_by_request_id[id] }

      @mutex.synchronize do
        @buffers[sid].finalize if sid && stop_reason == "end_turn"
        @prompt_session_by_request_id.delete(id)

        if @active_turn_request_id == id
          @active_turn_request_id = nil
          @turn_done.broadcast
        end
      end

      print "\n" if stop_reason == "end_turn"
      $stdout.flush
    end

    def handle_error_response(id, error, fatal: false)
      code = error["code"]
      message = error["message"] || error.to_s
      data = error["data"]
      protocol_error = ProtocolError.new(message, code: code, data: data)

      @mutex.synchronize do
        if fatal || id == JsonRpc::INITIALIZE_ID || id == JsonRpc::SESSION_NEW_ID
          @fatal_error = protocol_error
          @ready.broadcast
        else
          @error_by_request_id[id] = protocol_error
          if @active_turn_request_id == id
            @active_turn_request_id = nil
            @turn_done.broadcast
          end
        end
      end
    end
  end
end
