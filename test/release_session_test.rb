require "minitest/autorun"
require "pathname"
require "tmpdir"
require "fileutils"
require "open3"
require "json"

class ReleaseSessionTest < Minitest::Test
  HEAD = "f" * 40
  DIGEST = "sha256:#{'a' * 64}"
  REPOSITORY = "ghcr.io/andrerobitaille/two_rivers_reporter"

  def test_deploy_uses_the_verified_image_and_one_tunnel_until_the_operator_exits
    with_release do |root, environment|
      check_output, check_status = command(root, environment, "check")
      assert check_status.success?, check_output
      refute File.exist?("#{root}/events"), "Local check must not open SSH"
      blocked_output, blocked_status = command(root, environment, "setup")
      refute blocked_status.success?, blocked_output
      refute File.exist?("#{root}/events"), "Standalone setup must not open SSH"
      output, status = command(root, environment, "session", "release_deploy\nexit\n")
      assert status.success?, output
      events = events(root)
      assert_equal 1, events.count("OPEN"), events.inspect
      assert_equal 1, events.count("CLOSE"), events.inspect
      assert_equal "CLOSE", events.last
      assert events.any? { |event| event.start_with?("KAMAL deploy --skip-push") }
      assert events.any? { |event| event.start_with?("KAMAL build pull") }
      assert_equal 3, events.count("VERIFY"), events.inspect
      assert_includes events, "BOOT"
      assert_includes output, "Production verified at #{HEAD}"
      refute events.any? { |event| event.include?("build push") }
    end
  end

  def test_failed_deploy_keeps_the_session_for_inspection_without_an_automatic_retry
    with_release do |root, environment|
      output, status = command(root, environment.merge("FAIL_DEPLOY" => "1"), "session", "release_deploy\nrelease_ssh hostname </dev/null\nexit\n")
      assert status.success?, output
      assert_equal 1, events(root).count("OPEN")
      assert_equal 1, events(root).count("CLOSE")
      assert_equal 1, events(root).count { |event| event.start_with?("KAMAL deploy") }
      refute_includes events(root), "BOOT"
      assert_equal "SSH", events(root)[-2], "Inspection must happen before closing the session"
    end
  end

  def test_common_kamal_helper_uses_the_session_config_and_stops_when_the_tunnel_is_lost
    with_release do |root, environment|
      input = "export SSH_AUTH_SOCK=synthetic-agent\ncd /\nrelease_kamal app details\ntouch \"$TEST_ROOT/disconnected\"\nrelease_kamal app details\nexit 0\n"
      output, status = command(root, environment, "session", input)
      assert status.success?, output
      inspections = events(root).grep(/\AKAMAL app details /)
      assert_equal 1, inspections.size, events(root).inspect
      assert_match(%r{ -c /tmp/trr-production-release\.[^/ ]+/deploy\.yml\z}, inspections.first)
      assert_includes output, "Release tunnel is unavailable"
      assert_equal 1, events(root).count("OPEN")
      assert_equal 1, events(root).count("CLOSE")
      assert_equal "CLOSE", events(root).last
    end
  end

  def test_common_kamal_helper_refuses_a_caller_supplied_configuration
    with_release do |root, environment|
      input = "release_kamal app details -c other.yml\nrelease_kamal app details --config-file=other.yml\nexit 0\n"
      output, status = command(root, environment, "session", input)
      assert status.success?, output
      assert_equal 2, output.scan("release_kamal selects the session configuration").size
      assert_empty events(root).grep(/\AKAMAL app details /)
      assert_equal 1, events(root).count("OPEN")
      assert_equal 1, events(root).count("CLOSE")
    end
  end

  def test_missing_or_invalid_digest_cannot_fall_back_to_a_production_build
    [ "", "latest", "sha256:wrong" ].each do |digest|
      with_release do |root, environment|
        output, = command(root, environment.merge("RELEASE_IMAGE_DIGEST" => digest), "session", "release_deploy\nexit\n")
        assert_includes output, "must be the verified sha256 digest"
        refute events(root).any? { |event| event.start_with?("KAMAL deploy", "KAMAL build") }
        assert_equal 1, events(root).count("OPEN")
        assert_equal 1, events(root).count("CLOSE")
      end
    end
  end

  def test_wrong_digest_revision_service_or_architecture_prevents_app_replacement
    [ [ "digests", [ "#{REPOSITORY}@sha256:#{'b' * 64}" ], "digest mismatch" ],
      [ "labels", { "service" => "another_app", "org.opencontainers.image.revision" => HEAD }, "service mismatch" ],
      [ "labels", { "service" => "two_rivers_reporter", "org.opencontainers.image.revision" => "e" * 40 }, "revision mismatch" ],
      [ "architecture", "arm64", "linux/amd64" ] ].each do |key, value, message|
      with_release do |root, environment|
        metadata = image_metadata.merge(key => value)
        output, = command(root, environment.merge("IMAGE_METADATA" => metadata.to_json), "session", "release_deploy\nexit\n")
        assert_includes output, message
        refute events(root).any? { |event| event.start_with?("KAMAL deploy") }
        refute_includes events(root), "BOOT"
        assert_equal 1, events(root).count("OPEN")
      end
    end
  end

  def test_pre_deploy_hook_rejects_an_image_changed_by_the_final_pull
    with_release do |root, environment|
      changed = image_metadata.merge("digests" => [ "#{REPOSITORY}@sha256:#{'c' * 64}" ])
      output, = command(root, environment.merge("POST_PULL_IMAGE_METADATA" => changed.to_json), "session", "release_deploy\nexit\n")
      refute_includes events(root), "BOOT"
      assert_includes output, "digest mismatch"
      assert_equal 2, events(root).count("VERIFY")
      assert_equal 1, events(root).count("CLOSE")
    end
  end

  def test_lost_tunnel_stops_deployment_without_opening_a_replacement
    with_release do |root, environment|
      output, = command(root, environment, "session", "touch disconnected\nrelease_deploy\nexit\n")
      assert_includes output, "Release tunnel is unavailable"
      refute events(root).any? { |event| event.start_with?("KAMAL deploy", "KAMAL build") }
      assert_equal 1, events(root).count("OPEN")
    end
  end

  def test_image_verification_cannot_run_outside_the_owned_session
    with_release do |root, environment|
      output, status = command(root, environment, "verify-image")
      refute status.success?, output
      assert_includes output, "requires an active release session"
      refute File.exist?("#{root}/events")
    end
  end

  def test_pre_build_hook_refuses_a_default_kamal_build
    output, status = Open3.capture2e("bash", File.expand_path("../.kamal/hooks/pre-build", __dir__))
    refute status.success?, output
    assert_includes output, "isolated CI runner"
  end

  def test_dirty_or_unpushed_checkout_stops_before_pulling_or_replacing_an_image
    [ { "DIRTY_CHECKOUT" => "1" }, { "REMOTE_HEAD" => "e" * 40 } ].each do |change|
      with_release do |root, environment|
        output, = command(root, environment.merge(change), "session", "release_deploy\nexit\n")
        refute events(root).any? { |event| event.start_with?("KAMAL build", "KAMAL deploy") }, output
        refute_includes events(root), "BOOT"
      end
    end
  end

  private

  def image_metadata
    { "digests" => [ "#{REPOSITORY}@#{DIGEST}" ], "os" => "linux", "architecture" => "amd64",
      "labels" => { "service" => "two_rivers_reporter", "org.opencontainers.image.revision" => HEAD } }
  end

  def events(root)
    File.readlines("#{root}/events", chomp: true)
  end

  def command(root, environment, action, input = "")
    Open3.capture2e(environment, "bash", "#{root}/bin/release", action, stdin_data: input)
  end

  def with_release
    Dir.mktmpdir("release-session-test") do |root|
      %w[bin lib config fake .kamal/hooks script].each { |path| FileUtils.mkdir_p("#{root}/#{path}") }
      %w[bin/release bin/publish-image lib/release_image.sh config/deploy.yml .kamal/hooks/pre-build .kamal/hooks/pre-deploy script/build_production_image].each do |path|
        FileUtils.cp(Pathname.new(File.expand_path("..", __dir__)).join(path), "#{root}/#{path}")
      end
      File.write("#{root}/identity", "test-only")
      File.write("#{root}/config/master.key", "test-only")
      File.write("#{root}/ssh-config", "")
      fake = <<~'SH'
        #!/usr/bin/env bash
        case "${0##*/}" in
          ssh)
            case " $* " in
              *" -G "*) printf 'identityfile %s/identity\n' "$TEST_ROOT" ;;
              *" ControlMaster=yes "*) echo OPEN >> "$TEST_ROOT/events" ;;
              *" -O exit "*) echo CLOSE >> "$TEST_ROOT/events" ;;
              *" -O check "*) [[ ! -f "$TEST_ROOT/disconnected" ]] ;;
              *"docker image inspect"*) echo VERIFY >> "$TEST_ROOT/events"; printf '%s\n' "$IMAGE_METADATA" ;;
              *"docker inspect --format"*) printf 'sha256:%064d\n' 1 ;;
              *"legion_post_165_wi_tools"*) printf '%s\n' 'aaa legion_post_165_wi_tools-web-old' 'bbb legion_post_165_wi_public-web-old' ;;
              *"label=service=two_rivers_reporter"*) echo "two_rivers_reporter-web-$TEST_HEAD" ;;
              *) echo SSH >> "$TEST_ROOT/events" ;;
            esac ;;
          git)
            case "$1" in
              symbolic-ref) echo codex/test ;;
              rev-parse) echo "$TEST_HEAD" ;;
              ls-remote) printf '%s\trefs/heads/codex/test\n' "${REMOTE_HEAD:-$TEST_HEAD}" ;;
              diff) [[ "${DIRTY_CHECKOUT:-}" != 1 ]] ;;
            esac ;;
          ruby)
            [[ "$1" != -rsocket ]] || exit 0
            exec "$TEST_RUBY" "$@" ;;
          socat) exit 0 ;;
          timeout) shift 2; exec "$@" ;;
          kamal)
            [[ -z "${SSH_AUTH_SOCK:-}" && "$PWD" == "$TEST_ROOT" ]] || exit 1
            echo "KAMAL $*" >> "$TEST_ROOT/events"
            if [[ "$1" == deploy ]]; then
              [[ "${FAIL_DEPLOY:-}" != 1 ]] || exit 1
              [[ -z "${POST_PULL_IMAGE_METADATA:-}" ]] || export IMAGE_METADATA="$POST_PULL_IMAGE_METADATA"
              export KAMAL_VERSION="$TEST_HEAD"
              .kamal/hooks/pre-deploy || exit "$?"
              echo BOOT >> "$TEST_ROOT/events"
            fi ;;
        esac
      SH
      %w[ssh git ruby socat curl timeout].each do |name|
        File.write("#{root}/fake/#{name}", name == "curl" ? "#!/usr/bin/env bash\n[[ \"$*\" != */admin* ]] && printf 200 || printf 302\n" : fake)
        File.chmod(0o755, "#{root}/fake/#{name}")
      end
      File.write("#{root}/bin/kamal", fake)
      File.chmod(0o755, "#{root}/bin/kamal")
      environment = {
        "PATH" => "#{root}/fake:#{ENV.fetch('PATH')}", "TEST_ROOT" => root, "TEST_HEAD" => HEAD,
        "TEST_RUBY" => RbConfig.ruby, "IMAGE_METADATA" => image_metadata.to_json,
        "RELEASE_SSH_CONFIG" => "#{root}/ssh-config", "RELEASE_IMAGE_DIGEST" => DIGEST,
        "TWO_RIVERS_REPORTER_DATABASE_PASSWORD" => "test-only",
        "RELEASE_CONTROL_PATH" => nil, "SSH_AUTH_SOCK" => nil
      }
      yield root, environment
    end
  end
end
