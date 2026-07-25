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

  private

    def stub_gated(value)
      @gated = value
    end

    def gated_for_visitor?
      @gated
    end
end
