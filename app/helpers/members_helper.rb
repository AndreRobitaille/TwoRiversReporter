module MembersHelper
  def attendance_sentence(attendance)
    parts = [ "Present at #{attendance[:present]} of #{attendance[:total]} recorded meetings" ]
    details = []
    details << "excused from #{attendance[:excused]}" if attendance[:excused] > 0
    details << "absent from #{attendance[:absent]}" if attendance[:absent] > 0
    parts << details.join(", ") if details.any?
    parts.join(". ") + "."
  end
end
