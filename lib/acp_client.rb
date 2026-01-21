# frozen_string_literal: true

require_relative "acp_client/version"
require_relative "acp_client/errors"
require_relative "acp_client/message_buffer"
require_relative "acp_client/json_rpc"
require_relative "acp_client/process_manager"
require_relative "acp_client/response_handler"
require_relative "acp_client/client"

module AcpClient
  def self.new
    Client.new
  end
end
