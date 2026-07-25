require "test_helper"

class AccessHelperTest < ActionView::TestCase
  include AccessHelper

  test "returns full text untouched when not gated" do
    stub_gated(false)

    result = teaser("The quick brown fox jumps over the lazy dog", chars: 10)

    assert_equal "The quick brown fox jumps over the lazy dog", result
    assert_no_match(/teaser-fade/, result)
  end

  test "truncates at a word boundary when gated" do
    stub_gated(true)

    result = teaser("The quick brown fox jumps over the lazy dog", chars: 15)

    assert_match(/teaser-fade/, result)
    assert_match(/The quick/, result)
    assert_no_match(/lazy dog/, result)
  end

  test "does not append an ellipsis" do
    stub_gated(true)

    result = teaser("The quick brown fox jumps over the lazy dog", chars: 15)

    assert_no_match(/\.\.\./, result)
    assert_no_match(/…/, result)
  end

  test "leaves short text intact but still marks it faded" do
    stub_gated(true)

    result = teaser("Short", chars: 100)

    assert_match(/Short/, result)
    assert_match(/teaser-fade/, result)
  end

  test "escapes html_safe input even when short enough that no truncation fires" do
    stub_gated(true)

    result = teaser("<script>evil()</script>".html_safe, chars: 500)

    assert_no_match(/<script>/, result)
    assert_match(/&lt;script&gt;/, result)
  end

  test "returns nil for blank text" do
    stub_gated(true)

    assert_nil teaser(nil, chars: 10)
    assert_nil teaser("", chars: 10)
  end

  test "inline fade uses the inline modifier class" do
    stub_gated(true)

    result = teaser("The quick brown fox jumps over the lazy dog", chars: 15, fade: :inline)

    assert_match(/teaser-fade--inline/, result)
  end

  test "escapes markup in the source text" do
    stub_gated(true)

    result = teaser("<script>alert(1)</script> and more words here", chars: 200)

    assert_no_match(/<script>/, result)
    assert_match(/&lt;script&gt;/, result)
  end

  # ---------------------------------------------------------------- skeleton
  #
  # These guard the side channel, not the looks. Each one pins a property that,
  # if lost, would let an anonymous visitor read something about the withheld
  # text out of the placeholder geometry.

  # 300 and 140 characters — different lengths, same bucket (bound 120..320).
  SAME_BUCKET_LONG = ("alpha " * 50).strip.freeze
  SAME_BUCKET_SHORT = ("beta " * 28).strip.freeze

  test "two items in the same length bucket render byte-identical bars" do
    assert_operator SAME_BUCKET_LONG.length, :>, SAME_BUCKET_SHORT.length + 100,
      "fixture must differ enough in length that unquantized output would diverge"

    assert_equal skeleton_bars(SAME_BUCKET_SHORT, index: 0),
      skeleton_bars(SAME_BUCKET_LONG, index: 0),
      "bar geometry must not vary with the exact character count inside a bucket"
  end

  test "line count is capped so long and enormous items look the same" do
    long = "word " * 200      # 1000 chars
    enormous = "word " * 4000 # 20000 chars

    assert_equal 4, skeleton_lines(long, index: 0).size
    assert_equal skeleton_lines(long, index: 0), skeleton_lines(enormous, index: 0)
  end

  test "bar geometry is stable across renders of the same item" do
    first = skeleton_bars("some withheld prose about the harbor", index: 3)
    second = skeleton_bars("some withheld prose about the harbor", index: 3)

    assert_equal first, second, "the page must not reflow between loads"
  end

  test "no word of the source text reaches the rendered bars" do
    markup = skeleton_bars("dredging easement variance moratorium", index: 1) +
      skeleton_title_bar("dredging easement variance moratorium")

    %w[dredging easement variance moratorium].each do |word|
      assert_no_match(/#{word}/i, markup)
    end
    assert_no_match(/\d{2,}/, markup, "no raw measurement may reach the markup")
  end

  test "bar widths come from the fixed vocabulary only" do
    widths = skeleton_lines("a" * 900, index: 7).flatten.uniq

    assert_operator widths.size, :>, 0
    assert_empty widths - %w[s m l xl full],
      "a width outside the fixed bucket set means something is being computed from the text"
  end

  private

    def stub_gated(value)
      @gated = value
    end

    def gated_for_visitor?
      @gated
    end
end
