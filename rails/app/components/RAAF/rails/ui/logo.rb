# frozen_string_literal: true

require "base64"

module RAAF
  module Rails
    module Ui
      ##
      # The RAAF mark, inlined as a data URI.
      #
      # Same reasoning as {Stylesheet}: the dashboard is a mountable engine and
      # cannot assume the host application serves the engine's assets, so the
      # image travels with the markup instead of through an asset URL. The PNG
      # itself stays a normal file on disk.
      #
      module Logo
        PATH = ::File.expand_path("../../../../assets/images/RAAF/raaf-logo.png", __dir__)

        class << self
          # @return [String] the mark as a `data:image/png;base64,...` URI
          def data_uri
            @data_uri ||= "data:image/png;base64,#{::Base64.strict_encode64(::File.binread(PATH))}"
          end
        end
      end
    end
  end
end
