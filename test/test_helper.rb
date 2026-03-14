# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "acp_client"

require "minitest/autorun"

class MockProcessManager
  attr_reader :messages_sent, :stdout_lines, :stderr_lines

  def initialize
    @messages_sent = []
    @stdout_io = nil
    @stderr_io = nil
  end

  def start
    @stdout_reader, @stdout_writer = IO.pipe
    @stderr_reader, @stderr_writer = IO.pipe
    @stdout_lines = []
    @stderr_lines = []
  end

  def stdout
    @stdout_reader
  end

  def stderr
    @stderr_reader
  end

  def send_message(message)
    @messages_sent << message
  end

  def inject_stdout_line(json)
    @stdout_writer.puts(json)
    @stdout_writer.flush
  end

  def close
    @stdout_writer&.close
    @stderr_writer&.close
  end
end
