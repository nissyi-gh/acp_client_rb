# frozen_string_literal: true

require "json"

module AcpClient
  class ResponseHandler
    attr_reader :session_id, :initialized

    def initialize(process_manager:, json_rpc:)
      @process_manager = process_manager
      @json_rpc = json_rpc

      @mutex = Mutex.new
      @ready = ConditionVariable.new
      @turn_done = ConditionVariable.new

      @session_id = nil
      @initialized = false

      @buffers = Hash.new { |h, sid| h[sid] = MessageBuffer.new }
      @available_commands_by_session = {}

      @prompt_session_by_request_id = {}
      @active_turn_request_id = nil

      @reader_thread = nil
      @stderr_thread = nil
      @on_text_chunk = nil
    end

    def on_text_chunk(&block)
      @on_text_chunk = block
    end

    def start_threads
      start_stderr_thread
      start_reader_thread
    end

    def stop_threads
      @reader_thread&.kill rescue nil
      @stderr_thread&.kill rescue nil
    end

    def wait_for_ready
      @mutex.synchronize do
        @ready.wait(@mutex) until @initialized
      end
    end

    def wait_for_turn_completion(request_id)
      @mutex.synchronize do
        @turn_done.wait(@mutex) while @active_turn_request_id == request_id
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
      else
        handle_response(msg)
      end
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
      end
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
        handle_initialize_response
        return
      end

      if id == JsonRpc::SESSION_NEW_ID && msg["result"]
        handle_session_new_response(msg["result"])
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

    def handle_initialize_response
      message = @json_rpc.session_new_message
      @process_manager.send_message(message)
    end

    def handle_session_new_response(result)
      sid = result["sessionId"] || result["id"] || result["session_id"]
      raise SessionError, "Could not find session id in response: #{result}" unless sid

      @mutex.synchronize do
        @session_id = sid
        @initialized = true
        @ready.broadcast
      end

      puts "\n[info] session_id=#{sid}"
      puts "[info] You can now type messages. Type 'exit' to quit."
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

    def handle_error_response(id, error)
      puts "\n[error] id=#{id} #{error}"

      @mutex.synchronize do
        if @active_turn_request_id == id
          @active_turn_request_id = nil
          @turn_done.broadcast
        end
      end
    end
  end
end
