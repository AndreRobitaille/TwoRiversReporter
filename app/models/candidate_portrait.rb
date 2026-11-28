class CandidatePortrait < ApplicationRecord
  belongs_to :member, optional: true

  def self.current_for(names_and_ids)
    portraits = where(member_id: names_and_ids.values.compact)
      .or(where(member_id: nil, name: names_and_ids.keys))
      .select(:id, :member_id, :name, :image_url, :source_url, :publisher)
    by_member = portraits.select(&:member_id).index_by(&:member_id)
    by_name = portraits.index_by(&:name)
    names_and_ids.to_h { |name, id| [ name, by_member[id] || by_name[name] ] }
  end

  def image_key
    Digest::SHA256.hexdigest(image_url).first(12)
  end
end
