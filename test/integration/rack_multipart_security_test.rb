require "test_helper"
require "rack/mock"
require "rack/multipart"

class RackMultipartSecurityTest < ActiveSupport::TestCase
  BOUNDARY = "SyntheticBoundary".freeze

  test "ordinary and quoted multipart forms preserve Unicode fields and uploaded bytes" do
    uploaded_bytes = "synthetic upload\x00\xFF".b
    body = [
      "--#{BOUNDARY}\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nCouncil caf\u00e9\r\n".b,
      "--#{BOUNDARY}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"synthetic.png\"\r\nContent-Type: image/png\r\n\r\n".b,
      uploaded_bytes,
      "\r\n--#{BOUNDARY}--\r\n".b
    ].join

    [ BOUNDARY, "\"#{BOUNDARY}\"" ].each do |boundary|
      params = parse_form(body, "multipart/form-data; boundary=#{boundary}")
      upload = params.fetch("file")
      begin
        assert_equal "Council caf\u00e9", params.fetch("title")
        assert_equal "synthetic.png", upload.fetch(:filename)
        assert_equal uploaded_bytes, upload.fetch(:tempfile).read
      ensure
        upload.fetch(:tempfile).close!
      end
    end
  end

  test "multipart forms reject duplicate boundaries including leading empty and extended parameters" do
    body = "--#{BOUNDARY}\r\nContent-Disposition: form-data; name=\"record\"\r\n\r\nsynthetic canary\r\n--#{BOUNDARY}--\r\n"
    [
      "boundary=; boundary=#{BOUNDARY}",
      "boundary=\"\"; boundary=#{BOUNDARY}",
      "boundary=\";boundary=#{BOUNDARY}\"",
      "boundary=\",boundary=#{BOUNDARY}\"",
      "boundary=#{BOUNDARY}; boundary*=utf-8''Other",
      "boundary*=utf-8''Other; boundary=#{BOUNDARY}",
      "boundary=#{BOUNDARY}; boundary*0=Other; boundary*1=Value"
    ].each do |parameters|
      assert_raises(Rack::Multipart::BoundaryTooLongError, parameters) do
        parse_form(body, "multipart/form-data; #{parameters}")
      end
    end
  end

  test "multipart parsing releases consumed chunks while preserving every distinct part" do
    chunk_size = 1024
    delimiter = "\r\n--#{BOUNDARY}\r\n"
    names = ("a00".."a63").to_a
    headers = names.map { |name| "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n" }
    value_size = chunk_size - delimiter.bytesize - headers.first.bytesize
    expected = names.to_h { |name| [ name, "record #{name}".ljust(value_size, ".") ] }

    # End reads both inside a part's headers and immediately before its body.
    [ 10, 0 ].each do |offset|
      body = "x" * (value_size + offset)
      names.zip(headers).each { |name, header| body << delimiter << header << expected.fetch(name) }
      body << "\r\n--#{BOUNDARY}--\r\n"

      parser = Rack::Multipart::Parser.new(BOUNDARY, Rack::Multipart::Parser::TEMPFILE_FACTORY,
        chunk_size, Rack::Utils.default_query_parser)
      parser.parse(StringIO.new(body))

      assert_equal expected, parser.result.params
      assert_operator parser.instance_variable_get(:@sbuf).string.bytesize, :<, 2 * chunk_size,
        "consumed parts must not accumulate in the parser's scan buffer (offset #{offset})"
    end
  end

  private

    def parse_form(body, content_type)
      env = Rack::MockRequest.env_for("/synthetic-form", method: "POST", input: body,
        "CONTENT_TYPE" => content_type)
      Rack::Request.new(env).POST
    end
end
