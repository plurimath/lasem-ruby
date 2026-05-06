# frozen_string_literal: true

module Lasem
  class Error < StandardError; end

  class DependencyError < Error; end

  class RenderError < Error; end
end
