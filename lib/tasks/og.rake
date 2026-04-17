namespace :og do
  desc "Generate public/og-image.png from app/views/og/default.html.erb"
  task generate: :environment do
    require "fileutils"
    require "open3"
    require "socket"

    output_path = Rails.root.join("public", "og-image.png").to_s
    tmp_path = Rails.root.join("tmp", "og-image-raw.png").to_s
    FileUtils.mkdir_p(File.dirname(tmp_path))

    chromium = %w[chromium chromium-browser google-chrome google-chrome-stable]
      .find { |cmd| system("which #{cmd} > /dev/null 2>&1") }
    abort "No Chromium binary found on PATH (tried: chromium, chromium-browser, google-chrome, google-chrome-stable)." if chromium.nil?

    port = find_free_port
    server_pid = spawn(
      { "RAILS_ENV" => "development" },
      "bin/rails", "server", "-p", port.to_s, "-b", "127.0.0.1",
      out: File::NULL, err: File::NULL
    )

    begin
      wait_for_server("http://127.0.0.1:#{port}/og/default")

      url = "http://127.0.0.1:#{port}/og/default"
      args = [
        chromium,
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--no-sandbox",
        "--window-size=1200,630",
        "--screenshot=#{tmp_path}",
        url
      ]
      system(*args) || abort("Chromium screenshot failed")

      abort "Chromium produced no output at #{tmp_path}" unless File.exist?(tmp_path)

      if system("which pngquant > /dev/null 2>&1")
        system("pngquant --force --quality=80-95 --output #{output_path} #{tmp_path}") ||
          FileUtils.cp(tmp_path, output_path)
      else
        warn "pngquant not on PATH — copying raw PNG. Install pngquant to get ~5-10x smaller file."
        FileUtils.cp(tmp_path, output_path)
      end

      size_kb = File.size(output_path) / 1024
      puts "Generated #{output_path} (#{size_kb} KB)"
      warn "WARNING: file exceeds 100 KB target." if size_kb > 100
    ensure
      Process.kill("TERM", server_pid) rescue nil
      Process.wait(server_pid) rescue nil
      FileUtils.rm_f(tmp_path)
    end
  end

  def find_free_port
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    port
  end

  def wait_for_server(url, timeout: 30)
    deadline = Time.now + timeout
    until Time.now > deadline
      begin
        require "net/http"
        response = Net::HTTP.get_response(URI(url))
        return if response.code.to_i < 500
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        sleep 0.25
      end
    end
    abort "Rails server on #{url} did not become ready within #{timeout}s"
  end
end
