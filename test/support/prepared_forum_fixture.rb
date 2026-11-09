module PreparedForumFixture
  def forum_export(turns: nil)
    turns ||= [
      [ "Moderator", "What should the city prioritize?" ],
      [ "Jordan Example", "Repair water lines before expanding roads." ],
      [ nil, "Thanks." ],
      [ "Taylor Example", "New housing should come with safe crossings." ],
      [ "Morgan Example", "Preserve public access along the shoreline." ],
      [ "Casey Example", "Review fees before raising property taxes." ],
      [ "Avery Example", "Keep the library open on Saturdays." ]
    ]
    names = turns.filter_map(&:first)
    annotations = []
    position = 0
    captions = +"WEBVTT\n\n"
    previous = nil
    turns.each_with_index do |(name, text), index|
      annotations << { "start" => position, "end" => position + text.split.size, "speaker" => names.index(name) } if name
      position += text.split.size
      captions << format("00:%02d:00.000 --> 00:%02d:59.000\n", index, index)
      captions << "#{previous}\n" if previous
      captions << "#{text}\n\n"
      previous = text
    end
    { "format" => "forum-speaker-desk", "version" => 1, "parserVersion" => 1,
      "title" => "Synthetic candidate forum · 2024", "sourceUrl" => "https://example.test/forum-recording",
      "names" => names, "annotations" => annotations, "wordCount" => position,
      "captions" => captions, "sourceSha256" => Digest::SHA256.hexdigest(captions),
      "transcriptionVerified" => false, "timingBasis" => "Caption timing" }
  end

  def forum_parameters(data = forum_export)
    file = Tempfile.new([ "forum-speakers", ".json" ])
    file.write(data.to_json)
    file.close
    { file: Rack::Test::UploadedFile.new(file.path, "application/json"),
      publisher: "Example Civic Association", published_on: "2024-03-12", election_on: "2024-04-02",
      speaker_verified: "1", gaps_are_moderator: "1" }
  end
end
