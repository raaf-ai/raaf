# frozen_string_literal: true

# The specs under spec/rails need Rails and a live database, which this gem's
# bundle does not always carry. Each of them bows out while loading; this
# reports that once for the whole run instead of once per file.
module RailsSpecSkip

  def self.announce(error)
    return if @announced

    @announced = true
    warn "Skipping spec/rails: #{error.message}"
  end

end
