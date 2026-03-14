# frozen_string_literal: true

require "open3"

module AcpClient
  class TerminalManager
    def initialize
      @mutex = Mutex.new
      @terminals = {}
      @next_id = 0
    end

    def create(session_id:, command:, args: [], env: [], cwd: nil, output_byte_limit: 1_048_576)
      cmd = [command, *args].map(&:to_s)
      env_hash = env.to_h { |e| [e["name"] || e[:name], e["value"] || e[:value]] }
      workdir = cwd || Dir.pwd

      stdin, stdout, stderr, wait_thr = Open3.popen3(env_hash, *cmd, chdir: workdir)

      terminal_id = @mutex.synchronize do
        id = "term_#{@next_id}"
        @next_id += 1
        @terminals[id] = {
          stdin: stdin,
          stdout: stdout,
          stderr: stderr,
          wait_thr: wait_thr,
          output: +"",
          output_byte_limit: output_byte_limit,
          truncated: false,
          exit_status: nil
        }
        id
      end

      start_output_reader(terminal_id)
      terminal_id
    end

    def output(terminal_id)
      @mutex.synchronize do
        t = @terminals[terminal_id]
        raise ProtocolError, "Unknown terminal: #{terminal_id}" unless t

        {
          output: t[:output].dup,
          truncated: t[:truncated],
          exitStatus: t[:exit_status]
        }.compact
      end
    end

    def wait_for_exit(terminal_id)
      t = @mutex.synchronize { @terminals[terminal_id] }
      raise ProtocolError, "Unknown terminal: #{terminal_id}" unless t

      status = t[:wait_thr].value

      @mutex.synchronize do
        t = @terminals[terminal_id]
        t[:exit_status] = format_exit_status(status) if t
      end

      format_exit_status(status)
    end

    def kill(terminal_id)
      t = @mutex.synchronize { @terminals[terminal_id] }
      raise ProtocolError, "Unknown terminal: #{terminal_id}" unless t

      return unless t[:wait_thr]&.alive?

      Process.kill("TERM", t[:wait_thr].pid)
    rescue Errno::ESRCH
      # already dead
    end

    def release(terminal_id)
      @mutex.synchronize do
        t = @terminals.delete(terminal_id)
        return unless t

        begin
          t[:stdin]&.close
        rescue
          nil
        end
        begin
          t[:stdout]&.close
        rescue
          nil
        end
        begin
          t[:stderr]&.close
        rescue
          nil
        end

        if t[:wait_thr]&.alive?
          begin
            Process.kill("TERM", t[:wait_thr].pid)
          rescue
            nil
          end
        end
      end
    end

    private

    def start_output_reader(terminal_id)
      Thread.new do
        t = @mutex.synchronize { @terminals[terminal_id] }
        next unless t

        stdout = t[:stdout]
        stderr = t[:stderr]
        limit = t[:output_byte_limit]
        wait_thr = t[:wait_thr]

        append_output = lambda do |text|
          @mutex.synchronize do
            t = @terminals[terminal_id]
            return unless t

            t[:output] << text
            while t[:output].bytesize > limit && (idx = t[:output].index("\n"))
              t[:output] = t[:output].byteslice((idx + 1)..) || +""
              t[:truncated] = true
            end
          end
        end

        threads = [
          Thread.new {
            begin
              stdout.each_line { |line| append_output.call(line) }
            rescue
              IOError
            end
          },
          Thread.new {
            begin
              stderr.each_line { |line| append_output.call("[stderr] #{line}") }
            rescue
              IOError
            end
          }
        ]
        threads.each(&:join)

        @mutex.synchronize do
          t = @terminals[terminal_id]
          return unless t

          status = wait_thr.value
          t[:exit_status] = format_exit_status(status)
        end
      end
    end

    def format_exit_status(process_status)
      return nil unless process_status

      {
        exitCode: process_status.exitstatus,
        signal: process_status.termsig
      }.compact
    end
  end
end
