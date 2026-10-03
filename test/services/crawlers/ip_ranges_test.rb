require "test_helper"
require "minitest/mock"

class Crawlers::IpRangesTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    @ranges = Crawlers::IpRanges.new(cache: @cache)
    @address = IPAddr.new("192.0.2.4")
  end

  test "valid official feed verifies IPv4 and IPv6 with CIDR boundaries" do
    refresh_with(prefixes: [ { ipv4Prefix: "192.0.2.0/24" }, { ipv6Prefix: "2001:db8::/48" } ])

    assert @ranges.include?(:google, @address)
    assert @ranges.include?(:google, IPAddr.new("192.0.2.255"))
    assert_not @ranges.include?(:google, IPAddr.new("192.0.3.0"))
    assert @ranges.include?(:google, IPAddr.new("2001:db8::12"))
    assert_not @ranges.include?(:google, IPAddr.new("2001:db9::12"))
  end

  test "refresh stores string prefixes under symbol keys and the cache coder keeps them" do
    @ranges.stub(:fetch, { prefixes: [ { ipv4Prefix: "40.77.167.0/24" } ] }.to_json) { @ranges.refresh(:bing) }
    snapshot = @cache.read(@ranges.cache_key(:bing))

    assert_equal [ "40.77.167.0/24" ], snapshot[:prefixes]
    assert snapshot.fetch(:prefixes).all?(String)
    assert_instance_of Integer, snapshot.fetch(:fetched_at)
    assert @ranges.include?(:bing, IPAddr.new("40.77.167.27"))

    loaded = Marshal.load(Marshal.dump(snapshot))
    assert_equal [ :prefixes, :fetched_at ], loaded.keys
    @cache.write(@ranges.cache_key(:bing), loaded)
    assert @ranges.include?(:bing, "40.77.167.27")

    @cache.write(@ranges.cache_key(:bing), { "prefixes" => [ "40.77.167.0/24" ], "fetched_at" => Time.current.to_i })
    assert_not @ranges.include?(:bing, IPAddr.new("40.77.167.27"))

    @cache.write(@ranges.cache_key(:bing), { prefixes: [ IPAddr.new("40.77.167.0/24") ], fetched_at: Time.current.to_i })
    assert_not @ranges.include?(:bing, IPAddr.new("40.77.167.27"))
  end

  test "missing expired and corrupt snapshots never authorize access" do
    assert_not @ranges.include?(:google, @address)
    refresh_with(prefixes: [ { ipv4Prefix: "192.0.2.0/24" } ])
    travel 49.hours do
      assert_not @ranges.include?(:google, @address)
    end

    [ { prefixes: [ "0.0.0.0/0" ], fetched_at: Time.current.to_i },
      { prefixes: [ "192.0.2.0/24" ], fetched_at: 1.minute.from_now.to_i },
      { prefixes: [ "192.0.2.0/24" ], fetched_at: 3.days.ago.to_i },
      { prefixes: nil, fetched_at: Time.current.to_i }, "invalid" ].each do |snapshot|
      @cache.write(@ranges.cache_key(:google), snapshot)
      assert_not @ranges.include?(:google, @address)
    end
  end

  test "cache read failure keeps optional crawler access closed" do
    @cache.stub(:read, ->(*) { raise ActiveRecord::ConnectionNotEstablished }) do
      assert_not @ranges.include?(:google, @address)
    end
  end

  test "malformed feeds do not replace or extend the lifetime of a good snapshot" do
    refresh_with(prefixes: [ { ipv4Prefix: "192.0.2.0/24" } ])
    before = @cache.read(@ranges.cache_key(:google))
    bad_feeds = [ "not-json", "[]", { prefixes: [] }.to_json,
      { prefixes: [ { ipv4Prefix: "0.0.0.0/0" } ] }.to_json,
      { prefixes: [ { ipv6Prefix: "::/0" } ] }.to_json,
      { prefixes: [ { ipv4Prefix: "10.0.0.0/16" } ] }.to_json,
      { prefixes: [ { ipv4Prefix: "192.0.2.4" } ] }.to_json,
      { prefixes: [ { ipv4Prefix: "not-a-cidr" } ] }.to_json,
      { prefixes: [ { ipv4Prefix: "2001:db8::/48" } ] }.to_json,
      { prefixes: [ { ipv4Prefix: "192.0.2.0/24", ipv6Prefix: "2001:db8::/48" } ] }.to_json,
      { prefixes: [ { unexpected: "192.0.2.0/24" } ] }.to_json,
      { prefixes: [ nil ] }.to_json,
      { prefixes: Array.new(Crawlers::IpRanges::MAX_PREFIXES + 1) { { ipv4Prefix: "192.0.2.0/24" } } }.to_json ]

    travel 1.hour do
      bad_feeds.each do |body|
        @ranges.stub(:fetch, body) { assert_raises(Crawlers::IpRanges::Error) { @ranges.refresh(:google) } }
        assert_equal before, @cache.read(@ranges.cache_key(:google))
        assert @ranges.include?(:google, @address)
      end
    end
  end

  test "network failures preserve a good snapshot without refreshing its timestamp" do
    refresh_with(prefixes: [ { ipv4Prefix: "192.0.2.0/24" } ])
    before = @cache.read(@ranges.cache_key(:google))
    @ranges.stub(:fetch, ->(*) { raise Net::ReadTimeout }) do
      assert_raises(Crawlers::IpRanges::Error) { @ranges.refresh(:google) }
    end
    assert_equal before, @cache.read(@ranges.cache_key(:google))
  end

  test "fetch uses the fixed HTTPS source with timeouts and rejects redirects" do
    captured = {}
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:read_body) { |&block| block.call({ prefixes: [ { ipv4Prefix: "192.0.2.0/24" } ] }.to_json) }
    http = Object.new
    http.define_singleton_method(:request) do |request, &block|
      captured[:path] = request.path
      block.call(response)
    end
    start = ->(host, port, **options, &block) do
      captured[:host] = host
      captured[:port] = port
      captured[:options] = options
      block.call(http)
    end

    Net::HTTP.stub(:start, start) { assert_equal 1, @ranges.refresh(:google) }
    assert_equal "developers.google.com", captured[:host]
    assert_equal "/static/crawling/ipranges/common-crawlers.json", captured[:path]
    assert_equal 443, captured[:port]
    assert_equal({ use_ssl: true, open_timeout: 5, read_timeout: 10, write_timeout: 5 }, captured[:options])

    response = Net::HTTPMovedPermanently.new("1.1", "301", "Moved")
    Net::HTTP.stub(:start, start) { assert_raises(Crawlers::IpRanges::Error) { @ranges.refresh(:google) } }
  end

  test "oversized network response is rejected before it can become an authorization snapshot" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:read_body) { |&block| block.call("x" * (Crawlers::IpRanges::MAX_BODY_BYTES + 1)) }
    http = Object.new
    http.define_singleton_method(:request) { |_, &block| block.call(response) }
    start = ->(*, **, &block) { block.call(http) }

    Net::HTTP.stub(:start, start) { assert_raises(Crawlers::IpRanges::Error) { @ranges.refresh(:google) } }
    assert_not @ranges.include?(:google, @address)
  end

  private

    def refresh_with(**data)
      @ranges.stub(:fetch, data.to_json) { @ranges.refresh(:google) }
    end
end
