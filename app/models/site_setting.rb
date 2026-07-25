class SiteSetting < ApplicationRecord
  ACCESS_MODES = %w[open gated].freeze

  validates :access_mode, inclusion: { in: ACCESS_MODES }
  validates :singleton_guard, inclusion: { in: [ 0 ] }

  # Never creates. A missing row falls back to the default rather than
  # writing during a GET.
  def self.instance
    first || new(access_mode: "open", singleton_guard: 0)
  end

  def self.access_mode
    instance.access_mode
  end

  def self.gated?
    access_mode == "gated"
  end
end
