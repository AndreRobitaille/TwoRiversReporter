require "mechanize"

url = "https://www.two-rivers.org/citycouncil/page/city-council-meeting-285"
agent = Mechanize.new
agent.user_agent_alias = 'Mac Safari'
agent.verify_mode = OpenSSL::SSL::VERIFY_NONE

page = agent.get(url)

container = page.at(".related_info.meeting_info")
puts "Container found: #{!!container}"

if container
  puts container.inner_html
else
  puts "Full HTML dump:"
  puts page.body
end
