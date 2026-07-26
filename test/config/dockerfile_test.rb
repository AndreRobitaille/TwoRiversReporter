require "test_helper"

class DockerfileTest < ActiveSupport::TestCase
  setup do
    @dockerfile = Rails.root.join("Dockerfile").read
  end

  test "production binaries and the Ruby image are immutable inputs" do
    assert_match(/\A# syntax=docker\/dockerfile:1@sha256:[0-9a-f]{64}\n/, @dockerfile)
    assert_includes @dockerfile, "ruby:$RUBY_VERSION-slim@$RUBY_IMAGE_DIGEST"
    assert_no_match(%r{/releases/latest/}, @dockerfile)
    assert_includes @dockerfile, "sha256sum --check --strict"
    assert_match(/ARG DENO_VERSION=\d+\.\d+\.\d+/, @dockerfile)
    assert_match(/ARG YT_DLP_VERSION=\d{4}\.\d{2}\.\d{2}/, @dockerfile)
  end

  test "production excludes development and test gems" do
    assert_includes @dockerfile, 'BUNDLE_WITHOUT="development:test"'
  end
end
