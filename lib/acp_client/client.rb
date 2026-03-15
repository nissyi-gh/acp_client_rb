# frozen_string_literal: true

module AcpClient
  class Client
    attr_reader :json_rpc, :process_manager, :response_handler

    def initialize(fs_read_text_file: nil, fs_write_text_file: nil, process_manager: nil)
      @json_rpc = JsonRpc.new
      @process_manager = process_manager || ProcessManager.new
      @response_handler = nil
      @fs_read_text_file = fs_read_text_file
      @fs_write_text_file = fs_write_text_file
    end

    def list_session_capability?
      caps = agent_capabilities
      caps["list"] == true || caps.dig("sessionCapabilities", "list") == true
    end

    def interactive_session!
      connect
      run_interactive_loop
    ensure
      shutdown
    end

    def connect(load_session_id: nil, create_session: true, cwd: Dir.pwd, mcp_servers: [])
      @process_manager.start

      @response_handler = ResponseHandler.new(
        process_manager: @process_manager,
        json_rpc: @json_rpc,
        load_session_id: load_session_id,
        create_session: create_session,
        cwd: cwd,
        mcp_servers: mcp_servers
      )

      @response_handler.on_fs_read_text_file(&@fs_read_text_file) if @fs_read_text_file
      @response_handler.on_fs_write_text_file(&@fs_write_text_file) if @fs_write_text_file

      @response_handler.on_text_chunk do |text|
        print text
        $stdout.flush
      end

      @response_handler.start_threads

      message = @json_rpc.initialize_message
      @process_manager.send_message(message)

      @response_handler.wait_for_ready
    end

    def list_sessions(cwd: nil, cursor: nil)
      raise SessionError, "Not connected" unless @response_handler
      unless list_session_capability?
        raise SessionError, "Agent does not support session/list (sessionCapabilities.list)"
      end

      request_id = @json_rpc.next_id
      @response_handler.register_pending_request(request_id)

      message = @json_rpc.session_list_message(request_id: request_id, cwd: cwd, cursor: cursor)
      @process_manager.send_message(message)

      result = @response_handler.wait_for_pending_response(request_id)
      {
        sessions: result["sessions"] || [],
        next_cursor: result["nextCursor"]
      }
    end

    def load_session(session_id, cwd: Dir.pwd, mcp_servers: [])
      raise SessionError, "Not connected" unless @response_handler
      caps = agent_capabilities
      unless caps["loadSession"] == true || caps.dig("sessionCapabilities", "loadSession") == true
        raise SessionError, "Agent does not support session/load (loadSession)"
      end

      request_id = @json_rpc.next_id
      @response_handler.register_session_load(request_id, session_id)

      message = @json_rpc.session_load_message(
        request_id: request_id,
        session_id: session_id,
        cwd: cwd,
        mcp_servers: mcp_servers
      )
      @process_manager.send_message(message)

      @response_handler.wait_for_session
    end

    # @param prompt [String, Array<Hash>] Text or ContentBlock array (text, image, audio, resource, resource_link)
    def send_prompt(prompt)
      session_id = @response_handler.current_session_id
      raise SessionError, "Session not ready" unless session_id

      content_blocks = normalize_prompt(prompt)
      validate_prompt_capabilities!(content_blocks)

      request_id = @json_rpc.next_id
      @response_handler.register_prompt(request_id, session_id)

      message = @json_rpc.session_prompt_message(
        request_id: request_id,
        session_id: session_id,
        prompt: content_blocks
      )
      @process_manager.send_message(message)

      @response_handler.wait_for_turn_completion(request_id)
    end

    def cancel_prompt
      session_id = @response_handler.current_session_id
      raise SessionError, "Session not ready" unless session_id

      @response_handler.cancel_pending_permission
      message = @json_rpc.session_cancel_message(session_id: session_id)
      @process_manager.send_message(message)
    end

    def agent_capabilities
      @response_handler&.agent_capabilities || {}
    end

    def shutdown
      @response_handler&.stop_threads
      @process_manager&.shutdown
    end

    def prompt_capabilities
      agent_capabilities.dig("promptCapabilities") || {}
    end

    private

    def normalize_prompt(prompt)
      case prompt
      when String
        [{type: "text", text: prompt}]
      when Array
        prompt.map { |block| block.is_a?(Hash) ? block : {type: "text", text: block.to_s} }
      else
        [{type: "text", text: prompt.to_s}]
      end
    end

    def validate_prompt_capabilities!(content_blocks)
      caps = prompt_capabilities
      return if caps.empty?

      content_blocks.each do |block|
        type = block[:type] || block["type"]
        case type.to_s
        when "text", "resource_link"
          # baseline, always supported
        when "image"
          raise SessionError, "Agent does not support image in prompt (promptCapabilities.image)" unless caps["image"]
        when "audio"
          raise SessionError, "Agent does not support audio in prompt (promptCapabilities.audio)" unless caps["audio"]
        when "resource"
          raise SessionError, "Agent does not support embedded resource in prompt (promptCapabilities.embeddedContext)" unless caps["embeddedContext"]
        end
      end
    end

    def run_interactive_loop
      loop do
        print "> "
        $stdout.flush

        user_input = $stdin.gets
        break if user_input.nil?

        text = user_input.chomp
        break if text == "exit" || text == "quit"
        next if text.strip.empty?

        send_prompt(text)
      end
    end
  end
end
