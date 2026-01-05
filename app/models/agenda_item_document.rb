class AgendaItemDocument < ApplicationRecord
  belongs_to :agenda_item
  belongs_to :meeting_document
end
