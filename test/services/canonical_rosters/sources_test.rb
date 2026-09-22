require "test_helper"

class CanonicalRosters::SourcesTest < ActiveSupport::TestCase
  test "parses the official city council roster and offices" do
    rows = [
      [ "Scott Stechmesser", "City Council President" ],
      [ "Shannon Derby", "City Council Vice President" ],
      *%w[Mark Doug Katherine Bill Darla Tim Adam].map { |name| [ "#{name} Member", "City Council Member" ] }
    ]
    html = rows.map do |name, title|
      %(<div class="views-row"><div class="blog-title">#{name}</div><div class="blog-body">#{title}</div></div>)
    end.join

    snapshot = CanonicalRosters::CityCouncilSource.new(
      fetcher: ->(_url) { %(<div id="embedded_pages_block">#{html}</div>) }
    ).call

    assert_equal 9, snapshot.entries.size
    assert_equal "City Council President", snapshot.entries.first.position_title
    assert_equal "chair", snapshot.entries.first.membership_role
    assert_equal "vice_chair", snapshot.entries.second.membership_role
    assert snapshot.entries.drop(2).all? { |entry| entry.membership_role == "member" }
  end

  test "parses the official city manager" do
    html = <<~HTML
      <table><tr>
        <td class="views-field-title">Kyle Kordell</td>
        <td class="views-field-field-position">City Manager</td>
      </tr></table>
    HTML

    snapshot = CanonicalRosters::CityManagerSource.new(fetcher: ->(_url) { html }).call

    assert_equal [ "Kyle Kordell" ], snapshot.entries.map(&:name)
    assert_equal "city_manager", snapshot.entries.first.position_kind
  end

  test "parses Explore Two Rivers board and staff" do
    paragraphs = [
      "Board President", "Michael Ditmer", "Board Vice-President", "Mike Mathis",
      "Board Treasurer", "Curt Andrews", "Board Secretary", "Todd Nilson",
      "Board Members", "Melissa Nyssen", "Erin Dembski", "Amanda La Tour",
      "Lyssa Schmidt", "Cherry Barbier", "Tourism Director", "Joseph L. Metzen"
    ].map { |text| "<p>#{text}</p>" }.join
    html = %(<div class="content_main"><div class="field-name-body"><div class="field-item" property="content:encoded">#{paragraphs}</div></div></div>)

    snapshot = CanonicalRosters::ExploreTwoRiversSource.new(fetcher: ->(_url) { html }).call
    director = snapshot.entries.last

    assert_equal 10, snapshot.entries.size
    assert_equal "Joe Metzen", director.name
    assert_equal "Joseph L. Metzen", director.source_name
    assert_equal "staff", director.membership_role
  end

  test "parses Main Street names without trailing punctuation" do
    paragraphs = [
      [ "Kristine Pigeon,", "President" ], [ "Travis Stevens,", "Vice-President" ],
      [ "Devin Kumbalek", "Secretary" ], [ "Nicholas Meissner,", "Treasurer" ],
      [ "Melissa Nyssen,", "Member" ], [ "Kyle Kordell,", "Two Rivers City Manager, appointed" ],
      [ "Brian Gallagher", "Member" ], [ "Darla LeClair,", "Two Rivers City Council Representative, appointed" ],
      [ "Steve Kanter", "Member" ], [ "Michael Ditmer,", "Member" ], [ "Jason Ring", "Director" ]
    ].map { |name, text| "<p>#{text} <strong>#{name}</strong></p>" }.join
    html = %(<article><div class="entry-content">#{paragraphs}</div></article>)

    snapshot = CanonicalRosters::MainStreetSource.new(fetcher: ->(_url) { html }).call

    assert_equal 11, snapshot.entries.size
    assert_equal "Kristine Pigeon", snapshot.entries.first.name
    assert_equal "City Manager", snapshot.entries.find { |entry| entry.name == "Kyle Kordell" }.membership_title
    assert_equal "staff", snapshot.entries.find { |entry| entry.name == "Jason Ring" }.membership_role
  end

  test "rejects a truncated roster" do
    html = %(<div id="embedded_pages_block"><div class="views-row"><div class="blog-title">One Person</div><div class="blog-body">City Council Member</div></div></div>)

    assert_raises CanonicalRosters::Parser::Error do
      CanonicalRosters::CityCouncilSource.new(fetcher: ->(_url) { html }).call
    end
  end
end
