require "minitest/autorun"
require "pathname"
require "tmpdir"
require_relative "../../lib/runtime_dependency_updater"

class RuntimeDependencyUpdaterTest < Minitest::Test
  def test_updates_ruby_and_binary_versions_with_their_matching_digests
    in_runtime_fixture do |root|
      updater = RuntimeDependencyUpdater.new(root: root, fetch_json: method(:fixture_response))

      changes = updater.changes
      updater.apply!(changes)

      dockerfile = root.join("Dockerfile").read
      assert_equal [ "Dockerfile", ".ruby-version" ], changes.map(&:path)
      assert_includes dockerfile, "# syntax=docker/dockerfile:1@sha256:#{digest("f")}"
      assert_includes dockerfile, "ARG RUBY_VERSION=4.1.0"
      assert_includes dockerfile, "ARG RUBY_IMAGE_DIGEST=sha256:#{digest("a")}"
      assert_includes dockerfile, "ARG DENO_VERSION=2.9.5"
      assert_includes dockerfile, "ARG DENO_SHA256=#{digest("b")}"
      assert_includes dockerfile, "ARG YT_DLP_VERSION=2026.08.01"
      assert_includes dockerfile, "ARG YT_DLP_SHA256=#{digest("c")}"
      assert_equal "ruby-4.1.0\n", root.join(".ruby-version").read
    end
  end

  def test_fails_closed_when_an_official_release_omits_its_asset_digest
    in_runtime_fixture do |root|
      fetcher = ->(url) {
        response = fixture_response(url)
        if url.include?("denoland/deno")
          response["assets"].first["digest"] = nil
        end
        response
      }

      error = assert_raises(RuntimeDependencyUpdater::Error) do
        RuntimeDependencyUpdater.new(root: root, fetch_json: fetcher).changes
      end

      assert_includes error.message, "did not provide a valid sha256 digest"
      assert_equal "ruby-4.0.0\n", root.join(".ruby-version").read
    end
  end

  def test_refuses_to_update_mismatched_ruby_version_files
    in_runtime_fixture do |root|
      root.join(".ruby-version").write("ruby-4.0.1\n")

      error = assert_raises(RuntimeDependencyUpdater::Error) do
        RuntimeDependencyUpdater.new(root: root, fetch_json: method(:fixture_response)).changes
      end

      assert_includes error.message, "must match before updating"
    end
  end

  def test_refuses_to_downgrade_a_dependency_when_release_metadata_is_stale
    in_runtime_fixture do |root|
      fetcher = ->(url) {
        response = fixture_response(url)
        response["tag_name"] = "v2.9.3" if url.include?("denoland/deno")
        response
      }

      error = assert_raises(RuntimeDependencyUpdater::Error) do
        RuntimeDependencyUpdater.new(root: root, fetch_json: fetcher).changes
      end

      assert_includes error.message, "would downgrade 2.9.4 to 2.9.3"
    end
  end

  private

    def in_runtime_fixture
      Dir.mktmpdir do |directory|
        root = Pathname(directory)
        root.join(".ruby-version").write("ruby-4.0.0\n")
        root.join("Dockerfile").write(<<~DOCKERFILE)
          # syntax=docker/dockerfile:1@sha256:#{digest("0")}
          ARG RUBY_VERSION=4.0.0
          ARG RUBY_IMAGE_DIGEST=sha256:#{digest("1")}
          ARG DENO_VERSION=2.9.4
          ARG DENO_SHA256=#{digest("2")}
          ARG YT_DLP_VERSION=2026.07.04
          ARG YT_DLP_SHA256=#{digest("3")}
        DOCKERFILE
        yield root
      end
    end

    def fixture_response(url)
      case url
      when %r{/library/ruby/tags\?}
        { "results" => [ { "name" => "4.0.1-slim" }, { "name" => "4.0.2-slim" }, { "name" => "4.1.0-slim" } ] }
      when %r{/library/ruby/tags/4.1.0-slim}
        docker_tag_response("a")
      when %r{/docker/dockerfile/tags/1}
        docker_tag_response("f")
      when %r{/denoland/deno/releases/latest}
        github_release_response("v2.9.5", RuntimeDependencyUpdater::DENO_ASSET, "b")
      when %r{/yt-dlp/yt-dlp/releases/latest}
        github_release_response("2026.08.01", RuntimeDependencyUpdater::YT_DLP_ASSET, "c")
      else
        flunk "Unexpected URL: #{url}"
      end
    end

    def docker_tag_response(character)
      {
        "images" => [
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8", "digest" => "sha256:#{digest("e")}" },
          { "os" => "linux", "architecture" => "amd64", "variant" => nil, "digest" => "sha256:#{digest(character)}" }
        ]
      }
    end

    def github_release_response(tag, asset_name, character)
      {
        "tag_name" => tag,
        "assets" => [ { "name" => asset_name, "digest" => "sha256:#{digest(character)}" } ]
      }
    end

    def digest(character)
      character * 64
    end
end
