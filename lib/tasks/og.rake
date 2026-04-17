namespace :og do
  desc "Generate public/og-image.png from app/views/og/default.html.erb"
  task generate: :environment do
    require "fileutils"

    output_path = Rails.root.join("public", "og-image.png").to_s
    tmp_dir = Rails.root.join("tmp")
    tmp_html = tmp_dir.join("og-default.html").to_s
    tmp_png = tmp_dir.join("og-image-raw.png").to_s
    FileUtils.mkdir_p(tmp_dir)

    chromium = %w[chromium chromium-browser google-chrome google-chrome-stable]
      .find { |cmd| system("which #{cmd} > /dev/null 2>&1") }
    abort "No Chromium binary found on PATH (tried: chromium, chromium-browser, google-chrome, google-chrome-stable)." if chromium.nil?

    # Render the ERB to a static file. Rails' dev-mode annotation comments
    # wrap the real <!DOCTYPE html>, which triggers quirks mode in Chromium
    # and breaks font metrics. Strip them before writing.
    html = ApplicationController.renderer.render(
      template: "og/default",
      layout: false
    )
    html = html.gsub(/<!--\s*(BEGIN|END) app\/views\/og\/default\.html\.erb\s*-->\n?/, "").lstrip
    File.write(tmp_html, html)

    begin
      url = "file://#{tmp_html}"
      args = [
        chromium,
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--no-sandbox",
        "--window-size=1200,630",
        "--virtual-time-budget=10000",
        "--run-all-compositor-stages-before-draw",
        "--screenshot=#{tmp_png}",
        url
      ]
      system(*args) || abort("Chromium screenshot failed")

      abort "Chromium produced no output at #{tmp_png}" unless File.exist?(tmp_png)

      if system("which pngquant > /dev/null 2>&1")
        system("pngquant --force --quality=80-95 --output #{output_path} #{tmp_png}") ||
          FileUtils.cp(tmp_png, output_path)
      else
        warn "pngquant not on PATH — copying raw PNG. Install pngquant to get ~5-10x smaller file."
        FileUtils.cp(tmp_png, output_path)
      end

      size_kb = File.size(output_path) / 1024
      puts "Generated #{output_path} (#{size_kb} KB)"
      warn "WARNING: file exceeds 100 KB target." if size_kb > 100
    ensure
      FileUtils.rm_f(tmp_png)
      FileUtils.rm_f(tmp_html)
    end
  end
end
