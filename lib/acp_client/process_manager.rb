# frozen_string_literal: true

require "open3"
require "json"

module AcpClient
  class ProcessManager
    ACP_COMMAND = "npx -y @zed-industries/claude-code-acp"

    attr_reader :stdin, :stdout, :stderr, :wait_thr

    def initialize
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @wait_thr = nil
      @running = false
    end

    def start
      raise ConnectionError, "Process already running" if @running

      @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(ACP_COMMAND)
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

      @stdin&.close rescue nil
      @stdout&.close rescue nil
      @stderr&.close rescue nil

      if @wait_thr&.alive?
        Process.kill("TERM", @wait_thr.pid) rescue nil
      end

      @running = false
    end

    def pid
      @wait_thr&.pid
    end
  end
end
