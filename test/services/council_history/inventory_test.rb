require "test_helper"

class CouncilHistory::InventoryTest < ActiveSupport::TestCase
  test "the city index and detail page distinguish confirmed minutes, a missing source and a canceled meeting" do
    inventory = CouncilHistory::Inventory.new(from: Date.new(2025, 4, 1), through: Date.new(2025, 4, 30))
    url = "https://www.two-rivers.org/files/april.pdf"
    rows = [
      [ "direct", "City Council", %(<a href="#{url}">Minutes</a>) ],
      [ "detail", "Plan Commission", "" ],
      [ "unavailable", "Safety Committee", "" ],
      [ "cancel", "Recreation Board (NO APRIL MEETING)", "" ]
    ]
    html = rows.map do |slug, title, links|
      %(<tr><td class="views-field-field-calendar-date"><span content="2025-04-14T17:30:00-05:00"></span></td>
        <td class="views-field-title">#{title}</td><td class="views-field-view-node"><a href="/#{slug}">Details</a></td>
        <td class="views-field-field-minutes">#{links}</td></tr>)
    end
    pages = { "/meetings" => %(<table class="views-table"><tbody>#{html.join}</tbody></table>),
      "/detail" => %(<div class="related_info meeting_info"><section class="minutes"><a href="/files/plan.pdf">Minutes</a></section></div>),
      "/unavailable" => "<html>Source unavailable</html>" }
    visited = []
    agent = Mechanize.new
    agent.define_singleton_method(:get) do |address|
      path = URI(address).path
      visited << path
      Nokogiri::HTML(pages.fetch(path))
    end
    listings = Mechanize.stub(:new, agent) { inventory.listings }
    assert_equal %w[/meetings /detail /unavailable], visited
    assert_equal url, listings.first.dig("documents", "minutes_pdf")
    assert_equal "https://www.two-rivers.org/files/plan.pdf", listings.second.dig("documents", "minutes_pdf")
    assert_equal %w[fetch_minutes fetch_minutes source_unavailable cancelled], CouncilHistory::Inventory.review(listings).pluck("disposition")
  end
end
