# frozen_string_literal: true

module AcpClient
  class Client
    attr_reader :json_rpc, :process_manager, :response_handler

    def initialize
      @json_rpc = JsonRpc.new
      @process_manager = ProcessManager.new
      @response_handler = nil
    end

    def interactive_session!
      connect
      run_interactive_loop
    ensure
      shutdown
    end

    def connect
      @process_manager.start

      @response_handler = ResponseHandler.new(
        process_manager: @process_manager,
        json_rpc: @json_rpc
      )

      @response_handler.on_text_chunk do |text|
        print text
        $stdout.flush
      end

      @response_handler.start_threads

      message = @json_rpc.initialize_message
      @process_manager.send_message(message)

      @response_handler.wait_for_ready
    end

    def send_prompt(text)
      session_id = @response_handler.current_session_id
      raise SessionError, "Session not ready" unless session_id

      request_id = @json_rpc.next_id
      @response_handler.register_prompt(request_id, session_id)

      message = @json_rpc.session_prompt_message(
        request_id: request_id,
        session_id: session_id,
        prompt_text: text
      )
      @process_manager.send_message(message)

      @response_handler.wait_for_turn_completion(request_id)
    end

    def shutdown
      @response_handler&.stop_threads
      @process_manager&.shutdown
    end

    private

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
