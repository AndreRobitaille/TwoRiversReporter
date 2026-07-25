require "test_helper"

class Admin::MembershipApplicationsHelperTest < ActionView::TestCase
  include Admin::MembershipApplicationsHelper

  test "a bare ten digit number is hyphenated" do
    assert_equal "920-555-0148", formatted_phone_number("9205550148")
  end

  test "the parenthesised form loses its parentheses" do
    assert_equal "920-555-0148", formatted_phone_number("(920) 555-0148")
  end

  test "dotted, spaced and already hyphenated forms all normalise" do
    assert_equal "920-555-0148", formatted_phone_number("920.555.0148")
    assert_equal "920-555-0148", formatted_phone_number("920 555 0148")
    assert_equal "920-555-0148", formatted_phone_number("920-555-0148")
  end

  test "a leading US country code is dropped" do
    assert_equal "920-555-0148", formatted_phone_number("19205550148")
    assert_equal "920-555-0148", formatted_phone_number("+1 (920) 555-0148")
    assert_equal "920-555-0148", formatted_phone_number("1-920-555-0148")
  end

  test "eleven digits that do not start with one are left alone" do
    assert_equal "29205550148", formatted_phone_number("29205550148")
  end

  test "a trailing extension survives and does not break the digit count" do
    assert_equal "920-555-0148 x12", formatted_phone_number("920-555-0148 x12")
    assert_equal "920-555-0148 x12", formatted_phone_number("(920) 555-0148 ext. 12")
    assert_equal "920-555-0148 x12", formatted_phone_number("920.555.0148 extension 12")
    assert_equal "920-555-0148 x12", formatted_phone_number("9205550148#12")
    assert_equal "920-555-0148 x1204", formatted_phone_number("1 920 555 0148 x1204")
  end

  test "letters make a number unformattable and it is returned as stored" do
    assert_equal "920-555-CALL", formatted_phone_number("920-555-CALL")
    assert_equal "1-800-FLOWERS", formatted_phone_number("1-800-FLOWERS")
  end

  test "too few digits is returned as stored rather than mangled" do
    assert_equal "555-0148", formatted_phone_number("555-0148")
    assert_equal "5550148", formatted_phone_number("5550148")
    assert_equal "920", formatted_phone_number("920")
  end

  test "too many digits is returned as stored" do
    assert_equal "+44 20 7946 0958", formatted_phone_number("+44 20 7946 0958")
    assert_equal "920555014812345", formatted_phone_number("920555014812345")
  end

  test "outright junk is returned as stored" do
    assert_equal "asdf", formatted_phone_number("asdf")
    assert_equal "n/a", formatted_phone_number("n/a")
    assert_equal "ask me", formatted_phone_number("ask me")
  end

  test "blank and nil produce no output rather than an exception" do
    assert_equal "", formatted_phone_number(nil)
    assert_equal "", formatted_phone_number("")
    assert_equal "   ", formatted_phone_number("   ")
  end

  test "surrounding whitespace does not defeat formatting" do
    assert_equal "920-555-0148", formatted_phone_number("  (920) 555-0148  ")
  end
end
