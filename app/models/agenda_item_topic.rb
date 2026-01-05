class AgendaItemTopic < ApplicationRecord
  belongs_to :agenda_item
  belongs_to :topic
end
