require "test_helper"
require "minitest/mock"

class Crawlers::RefreshIpRangesJobTest < ActiveSupport::TestCase
  test "refreshes every registered feed on each run" do
    refreshed = []
    ranges = Object.new
    ranges.define_singleton_method(:refresh) do |feed|
      refreshed << feed
      1
    end

    Crawlers::IpRanges.stub(:new, ranges) do
      2.times { Crawlers::RefreshIpRangesJob.new.perform }
    end

    assert_equal Crawlers::Providers::FEEDS.keys * 2, refreshed
  end

  test "one failing feed does not prevent the other feeds from refreshing" do
    refreshed = []
    ranges = Object.new
    ranges.define_singleton_method(:refresh) do |feed|
      refreshed << feed
      raise Crawlers::IpRanges::Error, "unavailable" if feed == :google
      1
    end

    Crawlers::IpRanges.stub(:new, ranges) do
      assert_raises(Crawlers::IpRanges::Error) { Crawlers::RefreshIpRangesJob.new.perform }
    end

    assert_equal Crawlers::Providers::FEEDS.keys, refreshed
  end
end
