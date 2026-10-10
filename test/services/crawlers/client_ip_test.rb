require "test_helper"

class Crawlers::ClientIpTest < ActiveSupport::TestCase
  setup do
    @resolver = Crawlers::ClientIp.new(trusted_proxies: [ IPAddr.new("127.0.0.1/32"), IPAddr.new("172.18.0.0/16") ])
  end

  test "direct connections ignore every forwarded address" do
    request = build_request(peer: "198.51.100.12", forwarded: "66.249.66.1")
    request.set_header("HTTP_CLIENT_IP", "66.249.66.1")
    request.set_header("HTTP_FORWARDED", "for=66.249.66.1")

    assert_equal "198.51.100.12", @resolver.call(request).to_s
  end

  test "trusted proxy chain stops at the closest untrusted client" do
    request = build_request(peer: "127.0.0.1", forwarded: "66.249.66.1, 198.51.100.12, 172.18.0.3")

    assert_equal "198.51.100.12", @resolver.call(request).to_s
  end

  test "verified crawler can arrive through Thruster and Kamal" do
    request = build_request(peer: "127.0.0.1", forwarded: "66.249.66.1, 172.18.0.3")

    assert_equal "66.249.66.1", @resolver.call(request).to_s
  end

  test "trusted peer without a public client does not invent one" do
    assert_equal "127.0.0.1", @resolver.call(build_request(peer: "127.0.0.1")).to_s
    assert_equal "127.0.0.1", @resolver.call(build_request(peer: "127.0.0.1", forwarded: "172.18.0.3")).to_s
  end

  test "malformed oversized and excessive forwarding chains fail closed" do
    [ "66.249.66.1/24", "unknown, 66.249.66.1", "66.249.66.1,", "x" * 4097,
      ([ "66.249.66.1" ] * 33).join(",") ].each do |forwarded|
      assert_nil @resolver.call(build_request(peer: "127.0.0.1", forwarded: forwarded)), forwarded
    end
    assert_nil @resolver.call(build_request(peer: "66.249.66.1/24"))
    assert_nil @resolver.call(build_request(peer: "not-an-ip"))
  end

  test "IPv4 mapped IPv6 addresses are normalized before trust checks" do
    request = build_request(peer: "::ffff:127.0.0.1", forwarded: "::ffff:66.249.66.1, 172.18.0.3")

    assert_equal "66.249.66.1", @resolver.call(request).to_s
  end

  private

    def build_request(peer:, forwarded: nil)
      ActionDispatch::TestRequest.create.tap do |request|
        request.set_header("REMOTE_ADDR", peer)
        request.set_header("HTTP_X_FORWARDED_FOR", forwarded)
      end
    end
end
