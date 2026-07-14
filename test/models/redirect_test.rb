require "test_helper"

class RedirectTest < ActiveSupport::TestCase
  test "normalizes source_path: leading slash, no trailing slash, strips query and whitespace" do
    r = Redirect.create!(source_path: "  topics/766/?ref=x#frag  ", destination: "/topics/176")
    assert_equal "/topics/766", r.source_path
  end

  test "keeps root path as single slash" do
    r = Redirect.create!(source_path: "/", destination: "/topics")
    assert_equal "/", r.source_path
  end

  test "normalizes a path destination with a leading slash" do
    r = Redirect.create!(source_path: "/old", destination: "topics/176")
    assert_equal "/topics/176", r.destination
  end

  test "leaves an absolute URL destination untouched" do
    r = Redirect.create!(source_path: "/old", destination: "https://example.com/x")
    assert_equal "https://example.com/x", r.destination
  end

  test "requires source_path and destination" do
    r = Redirect.new
    assert_not r.valid?
    assert_includes r.errors.attribute_names, :source_path
    assert_includes r.errors.attribute_names, :destination
  end

  test "rejects a self-referential redirect" do
    r = Redirect.new(source_path: "/loop", destination: "/loop/")
    assert_not r.valid?
    assert_includes r.errors.attribute_names, :destination
  end

  test "enforces unique source_path" do
    Redirect.create!(source_path: "/topics/766", destination: "/topics/176")
    dup = Redirect.new(source_path: "/topics/766", destination: "/topics/200")
    assert_not dup.valid?
    assert_includes dup.errors.attribute_names, :source_path
  end

  test "defaults status_code to 301" do
    r = Redirect.create!(source_path: "/old", destination: "/new")
    assert_equal 301, r.status_code
  end

  test "rejects an unsupported status code" do
    r = Redirect.new(source_path: "/old", destination: "/new", status_code: 500)
    assert_not r.valid?
  end

  test "lookup returns destination and status for a matching path, nil otherwise" do
    Redirect.create!(source_path: "/topics/766", destination: "/topics/176", status_code: 302)

    hit = Redirect.lookup("/topics/766")
    assert_equal "/topics/176", hit[:destination]
    assert_equal 302, hit[:status_code]

    assert_nil Redirect.lookup("/topics/999")
  end

  test "lookup cache reflects creates and deletes" do
    assert_nil Redirect.lookup("/a")
    r = Redirect.create!(source_path: "/a", destination: "/b")
    assert_equal "/b", Redirect.lookup("/a")[:destination]
    r.destroy!
    assert_nil Redirect.lookup("/a")
  end

  test "upsert_redirect creates then updates the destination for a source" do
    Redirect.upsert_redirect(source_path: "/topics/766", destination: "/topics/176")
    assert_equal "/topics/176", Redirect.find_by(source_path: "/topics/766").destination

    Redirect.upsert_redirect(source_path: "/topics/766", destination: "/topics/200")
    assert_equal 1, Redirect.where(source_path: "/topics/766").count
    assert_equal "/topics/200", Redirect.find_by(source_path: "/topics/766").destination
  end
end
