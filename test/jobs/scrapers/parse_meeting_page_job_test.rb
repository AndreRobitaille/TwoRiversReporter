require "test_helper"

class Scrapers::ParseMeetingPageJobTest < ActiveJob::TestCase
  test "extracts documents with normalized absolute source urls and enqueues downloads" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/meetings/123", starts_at: Time.current)

    page = Object.new
    page.define_singleton_method(:at) do |selector|
      if selector == ".related_info.meeting_info"
        container = Object.new
        container.define_singleton_method(:at) do |inner_selector|
          next if inner_selector == ".packets"

          if inner_selector == ".agendas"
            section = Object.new
            section.define_singleton_method(:search) do |_|
              [
                Object.new.tap { |link| link.define_singleton_method(:[]) { |key| key == "href" ? "/docs/agenda.html" : nil } },
                Object.new.tap { |link| link.define_singleton_method(:[]) { |key| key == "href" ? "files/agenda.pdf" : nil } }
              ]
            end
            section
          elsif inner_selector == ".minutes"
            section = Object.new
            section.define_singleton_method(:search) do |_|
              [ Object.new.tap { |link| link.define_singleton_method(:[]) { |key| key == "href" ? "https://cdn.example.com/minutes.pdf" : nil } } ]
            end
            section
          end
        end
        container
      end
    end

    agent = Object.new
    agent.define_singleton_method(:user_agent_alias=) { |_alias_name| }
    agent.define_singleton_method(:get) { |_url| page }

    Mechanize.stub :new, agent do
      assert_enqueued_jobs 3, only: Documents::DownloadJob do
        Scrapers::ParseMeetingPageJob.perform_now(meeting.id)
      end
    end

    urls = meeting.reload.meeting_documents.order(:source_url).pluck(:source_url)
    assert_equal [
      "http://example.com/docs/agenda.html",
      "http://example.com/meetings/files/agenda.pdf",
      "https://cdn.example.com/minutes.pdf"
    ], urls

    assert_equal [ "agenda_html", "agenda_pdf", "minutes_pdf" ], meeting.meeting_documents.order(:source_url).pluck(:document_type)
  end

  test "stamps completion on successful no-doc parse" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/no-docs", starts_at: Time.current)

    agent = Object.new
    agent.define_singleton_method(:user_agent_alias=) { |_alias_name| }
    agent.define_singleton_method(:get) { |_url| Object.new.tap { |page| page.define_singleton_method(:at) { |_selector| nil } } }

    Mechanize.stub :new, agent do
      Scrapers::ParseMeetingPageJob.perform_now(meeting.id)
    end

    assert_equal true, meeting.reload.processing_state["meeting_page_parsed_at"]
  end

  test "does not stamp completion on fetch failure" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/fetch-failure", starts_at: Time.current)

    agent = Object.new
    agent.define_singleton_method(:user_agent_alias=) { |_alias_name| }
    agent.define_singleton_method(:get) { |_url| raise Mechanize::ResponseCodeError.new(nil, nil, nil) }

    Mechanize.stub :new, agent do
      Scrapers::ParseMeetingPageJob.perform_now(meeting.id)
    end

    assert_nil meeting.reload.processing_state["meeting_page_parsed_at"]
  end
end
