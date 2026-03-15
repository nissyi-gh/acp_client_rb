# frozen_string_literal: true

require "open3"
require "json"

module AcpClient
  class ProcessManager
    ACP_COMMAND = "npx -y @zed-industries/claude-code-acp"

    attr_reader :stdin, :stdout, :stderr, :wait_thr

    # @param command [String, nil] Agent command (default: ACP_COMMAND)
    # @param env [Hash, nil] Environment variables to merge with ENV (e.g. {"VAR" => "value"})
    def initialize(command: nil, env: nil)
      @command = command || ACP_COMMAND
      @env = env
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @wait_thr = nil
      @running = false
    end

    def start
      raise ConnectionError, "Process already running" if @running

      if @env && !@env.empty?
        merged_env = ENV.to_h.merge(@env.transform_keys(&:to_s))
        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(merged_env, @command)
      else
        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@command)
      end
      @running = true
    end

    def running?
      @running && @wait_thr&.alive?
    end

    def send_message(message)
      raise ConnectionError, "Process not running" unless running?

      json = message.is_a?(String) ? message : JSON.generate(message)
      @stdin.write(json)
      @stdin.write("\n")
      @stdin.flush
    end

    def shutdown
      return unless @running

      begin
        @stdin&.close
      rescue
        nil
      end
      begin
        @stdout&.close
      rescue
        nil
      end
      begin
        @stderr&.close
      rescue
        nil
      end

      if @wait_thr&.alive?
        begin
          Process.kill("TERM", @wait_thr.pid)
        rescue
          nil
        end
      end

      @running = false
    end

    def pid
      @wait_thr&.pid
    end
  end
end
