# frozen_string_literal: true

module AcpClient
  class MessageBuffer
    def initialize
      @mutex = Mutex.new
      @text = +""
    end

    def append_text(chunk)
      return if chunk.nil? || chunk.empty?

      @mutex.synchronize { @text << chunk }
    end

    def finalize
      @mutex.synchronize do
        out = @text.dup
        @text.clear
        out
      end
    end

    def clear
      @mutex.synchronize { @text.clear }
    end

    def text
      @mutex.synchronize { @text.dup }
    end
  end
end
