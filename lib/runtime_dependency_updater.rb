require "json"
require "net/http"
require "pathname"
require "uri"

class RuntimeDependencyUpdater
  class Error < StandardError; end

  Change = Data.define(:path, :before, :after)

  DENO_REPOSITORY = "denoland/deno"
  DENO_ASSET = "deno-x86_64-unknown-linux-gnu.zip"
  YT_DLP_REPOSITORY = "yt-dlp/yt-dlp"
  YT_DLP_ASSET = "yt-dlp_linux"

  def initialize(root:, fetch_json: nil)
    @root = Pathname(root)
    @fetch_json = fetch_json || method(:fetch_json)
  end

  def changes
    desired_files.filter_map do |path, desired_content|
      current_content = path.read
      next if current_content == desired_content

      Change.new(path: path.relative_path_from(root).to_s, before: current_content, after: desired_content)
    end
  end

  def apply!(planned_changes = changes)
    planned_changes.each do |change|
      root.join(change.path).write(change.after)
    end
  end

  private

    attr_reader :root

    def desired_files
      dockerfile_path = root.join("Dockerfile")
      ruby_version_path = root.join(".ruby-version")
      dockerfile = dockerfile_path.read
      ruby_file_version = extract_once!(ruby_version_path.read, /\Aruby-(\d+\.\d+\.\d+)\s*\z/, ".ruby-version")
      dockerfile_ruby_version = extract_once!(dockerfile, /^ARG RUBY_VERSION=(\d+\.\d+\.\d+)$/, "Dockerfile Ruby version")
      current_deno_version = extract_once!(dockerfile, /^ARG DENO_VERSION=(\d+\.\d+\.\d+)$/, "Deno version")
      current_yt_dlp_version = extract_once!(dockerfile, /^ARG YT_DLP_VERSION=(\d{4}\.\d{2}\.\d{2})$/, "yt-dlp version")

      unless ruby_file_version == dockerfile_ruby_version
        raise Error, ".ruby-version and Dockerfile RUBY_VERSION must match before updating"
      end

      ruby_version = latest_ruby_version(dockerfile_ruby_version)
      ruby_digest = docker_digest("library/ruby", "#{ruby_version}-slim")
      frontend_digest = docker_digest("docker/dockerfile", "1")
      deno_version, deno_digest = github_release(DENO_REPOSITORY, DENO_ASSET, prefix: "v")
      yt_dlp_version, yt_dlp_digest = github_release(YT_DLP_REPOSITORY, YT_DLP_ASSET)
      reject_downgrade!(deno_version, current_deno_version, "Deno")
      reject_downgrade!(yt_dlp_version, current_yt_dlp_version, "yt-dlp")

      updated_dockerfile = dockerfile
      updated_dockerfile = replace_once!(
        updated_dockerfile,
        %r{\A# syntax=docker/dockerfile:1@sha256:[0-9a-f]{64}$},
        "# syntax=docker/dockerfile:1@#{frontend_digest}",
        "Dockerfile frontend digest"
      )
      updated_dockerfile = replace_once!(
        updated_dockerfile,
        /^ARG RUBY_VERSION=\d+\.\d+\.\d+$/,
        "ARG RUBY_VERSION=#{ruby_version}",
        "Ruby version"
      )
      updated_dockerfile = replace_once!(
        updated_dockerfile,
        /^ARG RUBY_IMAGE_DIGEST=sha256:[0-9a-f]{64}$/,
        "ARG RUBY_IMAGE_DIGEST=#{ruby_digest}",
        "Ruby image digest"
      )
      updated_dockerfile = replace_once!(
        updated_dockerfile,
        /^ARG DENO_VERSION=\d+\.\d+\.\d+$/,
        "ARG DENO_VERSION=#{deno_version}",
        "Deno version"
      )
      updated_dockerfile = replace_once!(
        updated_dockerfile,
        /^ARG DENO_SHA256=[0-9a-f]{64}$/,
        "ARG DENO_SHA256=#{deno_digest.delete_prefix("sha256:")}",
        "Deno digest"
      )
      updated_dockerfile = replace_once!(
        updated_dockerfile,
        /^ARG YT_DLP_VERSION=\d{4}\.\d{2}\.\d{2}$/,
        "ARG YT_DLP_VERSION=#{yt_dlp_version}",
        "yt-dlp version"
      )
      updated_dockerfile = replace_once!(
        updated_dockerfile,
        /^ARG YT_DLP_SHA256=[0-9a-f]{64}$/,
        "ARG YT_DLP_SHA256=#{yt_dlp_digest.delete_prefix("sha256:")}",
        "yt-dlp digest"
      )

      {
        dockerfile_path => updated_dockerfile,
        ruby_version_path => "ruby-#{ruby_version}\n"
      }
    end

    def latest_ruby_version(current_version)
      query = URI.encode_www_form(name: "-slim", ordering: "last_updated", page_size: 100)
      payload = fetch("https://hub.docker.com/v2/repositories/library/ruby/tags?#{query}")
      versions = Array(payload["results"]).filter_map do |result|
        match = result.fetch("name", "").match(/\A(\d+\.\d+\.\d+)-slim\z/)
        match && match[1]
      end

      raise Error, "No stable Ruby slim image tags were returned by Docker Hub" if versions.empty?

      latest_version = versions.max_by { |version| version_key(version) }
      reject_downgrade!(latest_version, current_version, "Ruby")
      latest_version
    end

    def docker_digest(repository, tag)
      encoded_tag = URI.encode_www_form_component(tag)
      payload = fetch("https://hub.docker.com/v2/repositories/#{repository}/tags/#{encoded_tag}")
      image = Array(payload["images"]).find do |candidate|
        candidate["os"] == "linux" &&
          candidate["architecture"] == "amd64" &&
          candidate["variant"].to_s.empty?
      end

      validate_digest!(image&.fetch("digest", nil), "#{repository}:#{tag}")
    end

    def github_release(repository, asset_name, prefix: nil)
      payload = fetch("https://api.github.com/repos/#{repository}/releases/latest")
      tag = payload.fetch("tag_name")
      version = prefix ? tag.delete_prefix(prefix) : tag
      version_pattern = prefix ? /\A\d+\.\d+\.\d+\z/ : /\A\d{4}\.\d{2}\.\d{2}\z/
      raise Error, "Unexpected release tag #{tag.inspect} for #{repository}" unless version.match?(version_pattern)

      asset = Array(payload["assets"]).find { |candidate| candidate["name"] == asset_name }
      raise Error, "Release #{tag} for #{repository} has no #{asset_name} asset" unless asset

      [ version, validate_digest!(asset["digest"], "#{repository} #{tag} #{asset_name}") ]
    end

    def validate_digest!(digest, source)
      return digest if digest.to_s.match?(/\Asha256:[0-9a-f]{64}\z/)

      raise Error, "#{source} did not provide a valid sha256 digest"
    end

    def reject_downgrade!(candidate, current, name)
      return unless (version_key(candidate) <=> version_key(current)) == -1

      raise Error, "#{name} release metadata would downgrade #{current} to #{candidate}"
    end

    def version_key(version)
      version.split(".").map(&:to_i)
    end

    def extract_once!(content, pattern, label)
      matches = content.scan(pattern)
      raise Error, "Expected exactly one #{label}, found #{matches.length}" unless matches.one?

      matches.first.first
    end

    def replace_once!(content, pattern, replacement, label)
      matches = content.scan(pattern)
      raise Error, "Expected exactly one #{label}, found #{matches.length}" unless matches.one?

      content.sub(pattern, replacement)
    end

    def fetch(url)
      @fetch_json.call(url)
    end

    def fetch_json(url)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["User-Agent"] = "TwoRiversReporter-runtime-updater"
      request["Authorization"] = "Bearer #{ENV["GITHUB_TOKEN"]}" if uri.host == "api.github.com" && ENV["GITHUB_TOKEN"].to_s != ""

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 10,
        read_timeout: 30
      ) { |http| http.request(request) }

      raise Error, "#{url} returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "#{url} returned invalid JSON: #{e.message}"
    end
end
