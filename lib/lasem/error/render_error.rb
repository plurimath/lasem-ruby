# frozen_string_literal: true

require_relative "../error"

module Lasem
  class RenderError < StandardError
    include Error
  end
end
