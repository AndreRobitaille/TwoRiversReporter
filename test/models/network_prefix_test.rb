require "test_helper"

class NetworkPrefixTest < ActiveSupport::TestCase
  test "masks IPv4 to a /24" do
    assert_equal "203.0.113.0/24", NetworkPrefix.for("203.0.113.45")
  end

  test "two addresses inside one /24 produce the same prefix" do
    assert_equal NetworkPrefix.for("203.0.113.1"), NetworkPrefix.for("203.0.113.254")
  end

  test "addresses either side of a /24 boundary produce different prefixes" do
    assert_not_equal NetworkPrefix.for("203.0.113.254"), NetworkPrefix.for("203.0.114.1")
  end

  test "masks IPv6 to a /48" do
    assert_equal "2001:db8:1234::/48", NetworkPrefix.for("2001:db8:1234:5678::1")
  end

  test "two addresses inside one IPv6 /48 produce the same prefix" do
    assert_equal NetworkPrefix.for("2001:db8:1234:5678::1"), NetworkPrefix.for("2001:db8:1234:abcd::9")
  end

  test "an IPv4-mapped IPv6 address produces the same prefix as its plain form" do
    assert_equal NetworkPrefix.for("203.0.113.45"), NetworkPrefix.for("::ffff:203.0.113.45")
  end

  test "returns nil for blank input" do
    assert_nil NetworkPrefix.for(nil)
    assert_nil NetworkPrefix.for("")
    assert_nil NetworkPrefix.for("   ")
  end

  test "returns nil for unparseable input rather than raising" do
    assert_nil NetworkPrefix.for("not-an-ip")
    assert_nil NetworkPrefix.for("999.999.999.999")
    assert_nil NetworkPrefix.for("<script>")
  end
end
