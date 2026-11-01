require "minitest/autorun"
require "pathname"
require "tmpdir"
require "fileutils"
require "open3"
require "digest"
require "zlib"
require "json"

class PublishImageTest < Minitest::Test
  HEAD = "f" * 40
  DIGEST = "sha256:#{'a' * 64}"

  def test_verified_artifact_publishes_without_docker_or_persistent_credentials
    with_artifact do |root, environment|
      output, status = publish(root, environment)
      assert status.success?, output
      assert_includes output, "RELEASE_IMAGE_DIGEST=#{DIGEST}"
      refute_includes output, "test-only-token"
      events = File.readlines("#{root}/calls", chomp: true)
      assert events.any? { |line| line.include?("push ") && line.include?(":#{HEAD}") }
      auth = events.find { |line| line.start_with?("auth ") }
      assert auth
      refute File.exist?(auth.delete_prefix("auth ")), "Temporary registry credentials must be removed"
    end
  end

  def test_failed_wrong_revision_and_pull_request_workflows_cannot_publish
    [ { "conclusion" => "failure" }, { "head_sha" => "e" * 40 }, { "event" => "pull_request" },
      { "path" => ".github/workflows/another.yml" } ].each do |change|
      with_artifact do |root, environment|
        output, status = publish(root, environment.merge("TEST_RUN" => workflow.merge(change).to_json))
        refute status.success?, output
        refute File.exist?("#{root}/calls"), "Invalid runs must stop before registry access"
      end
    end
  end

  def test_corrupt_archive_stops_before_registry_login
    with_artifact do |root, environment|
      File.write("#{root}/artifact/image.tar.gz", "corrupted")
      output, status = publish(root, environment)
      refute status.success?, output
      assert_includes output, "FAILED"
      refute File.exist?("#{root}/calls")
    end
  end

  def test_invalid_compression_with_valid_checksums_stops_before_registry_login
    with_artifact do |root, environment|
      File.write("#{root}/artifact/image.tar.gz", "not gzip")
      checksum = Digest::SHA256.file("#{root}/artifact/image.tar.gz").hexdigest
      revision_checksum = Digest::SHA256.file("#{root}/artifact/revision.txt").hexdigest
      File.write("#{root}/artifact/SHA256SUMS", "#{checksum}  image.tar.gz\n#{revision_checksum}  revision.txt\n")
      output, status = publish(root, environment)
      refute status.success?, output
      assert_includes output, "not in gzip format"
      refute File.exist?("#{root}/calls")
    end
  end

  def test_incomplete_checksum_manifest_stops_before_registry_login
    with_artifact do |root, environment|
      checksum = Digest::SHA256.file("#{root}/artifact/revision.txt").hexdigest
      File.write("#{root}/artifact/SHA256SUMS", "#{checksum}  revision.txt\n")
      output, status = publish(root, environment)
      refute status.success?, output
      assert_includes output, "Both artifact checksums are required"
      refute File.exist?("#{root}/calls")
    end
  end

  def test_image_build_command_refuses_workstation_and_remote_docker_contexts
    output, status = Open3.capture2e({ "GITHUB_ACTIONS" => "", "DOCKER_HOST" => "" }, "bash", Pathname.new(File.expand_path("..", __dir__)).join("script/build_production_image").to_s, "HEAD", "/tmp/not-created-trr")
    refute status.success?, output
    assert_includes output, "isolated GitHub Actions runner"
    output, status = Open3.capture2e({ "GITHUB_ACTIONS" => "true", "DOCKER_HOST" => "ssh://production.invalid" }, "bash", Pathname.new(File.expand_path("..", __dir__)).join("script/build_production_image").to_s, "HEAD", "/tmp/not-created-trr")
    refute status.success?, output
    assert_includes output, "remote Docker host or overridden context is not allowed"
  end

  private

  def workflow
    { "status" => "completed", "conclusion" => "success", "head_sha" => HEAD,
      "path" => ".github/workflows/runtime-image.yml", "event" => "push" }
  end

  def publish(root, environment)
    Open3.capture2e(environment, "bash", "#{root}/bin/publish-image", "123")
  end

  def with_artifact
    Dir.mktmpdir("publish-image-test") do |root|
      %w[bin fake artifact].each { |path| FileUtils.mkdir_p("#{root}/#{path}") }
      FileUtils.cp(Pathname.new(File.expand_path("..", __dir__)).join("bin/publish-image"), "#{root}/bin/publish-image")
      Zlib::GzipWriter.open("#{root}/artifact/image.tar.gz") { |archive| archive.write("synthetic archive") }
      File.write("#{root}/artifact/revision.txt", "#{HEAD}\n")
      checksums = %w[image.tar.gz revision.txt].map { |name| "#{Digest::SHA256.file("#{root}/artifact/#{name}").hexdigest}  #{name}" }
      File.write("#{root}/artifact/SHA256SUMS", checksums.join("\n") + "\n")
      stub(root, "git", 'puts ENV.fetch("TEST_HEAD")')
      stub(root, "docker", 'abort "Docker must not be used"')
      stub(root, "gh", <<~'RUBY')
        require "fileutils"
        case ARGV.first
        when "api"
          puts ARGV[1] == "user" ? "synthetic-publisher" : ENV.fetch("TEST_RUN")
        when "run"
          target = ARGV[ARGV.index("--dir") + 1]
          FileUtils.cp(Dir["#{ENV.fetch('TEST_ROOT')}/artifact/*"], target)
        when "auth"
          puts "test-only-token"
        end
      RUBY
      stub(root, "crane", <<~'RUBY')
        require "json"
        File.open("#{ENV.fetch('TEST_ROOT')}/calls", "a") do |log|
          log.puts ARGV.first == "auth" ? "auth #{ENV.fetch('DOCKER_CONFIG')}" : ARGV.join(" ")
        end
        case ARGV.first
        when "auth" then STDIN.read
        when "push"
          abort "Expected an uncompressed archive" unless File.read(ARGV[1]) == "synthetic archive" && ARGV[1].end_with?("image.tar")
        when "digest" then puts ENV.fetch("TEST_DIGEST")
        when "config"
          puts JSON.generate("os" => "linux", "architecture" => "amd64", "config" => { "Labels" => {
            "service" => "two_rivers_reporter", "org.opencontainers.image.revision" => ENV.fetch("TEST_HEAD") } })
        end
      RUBY
      environment = { "PATH" => "#{root}/fake:#{ENV.fetch('PATH')}", "CRANE" => "#{root}/fake/crane",
        "TEST_ROOT" => root, "TEST_HEAD" => HEAD, "TEST_DIGEST" => DIGEST, "TEST_RUN" => workflow.to_json }
      yield root, environment
    end
  end

  def stub(root, name, code)
    File.write("#{root}/fake/#{name}", "#!#{RbConfig.ruby}\n#{code}\n")
    File.chmod(0o755, "#{root}/fake/#{name}")
  end
end
