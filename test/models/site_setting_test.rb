require "test_helper"

class SiteSettingTest < ActiveSupport::TestCase
  test "defaults to open when no row exists" do
    SiteSetting.delete_all

    assert_equal "open", SiteSetting.access_mode
    assert_not SiteSetting.gated?
  end

  test "reading does not create a row" do
    SiteSetting.delete_all

    SiteSetting.access_mode

    assert_equal 0, SiteSetting.count
  end

  test "gated? reflects the stored mode" do
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)

    assert SiteSetting.gated?
  end

  test "rejects an unknown access mode" do
    setting = SiteSetting.new(access_mode: "sideways", singleton_guard: 0)

    assert_not setting.valid?
    assert_includes setting.errors[:access_mode], "is not included in the list"
  end

  test "a second row is rejected" do
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "open", singleton_guard: 0)

    assert_raises(ActiveRecord::RecordNotUnique) do
      SiteSetting.insert!({ access_mode: "gated", singleton_guard: 0 })
    end
  end
end
