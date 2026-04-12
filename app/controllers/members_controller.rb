class MembersController < ApplicationController
  def show
    @member = Member.find(params[:id])

    @memberships = @member.committee_memberships
      .where(ended_on: nil)
      .where("role IS NULL OR role NOT IN (?)", %w[staff non_voting])
      .includes(:committee)
      .sort_by { |cm| [ cm.committee.name == "City Council" ? 0 : 1, cm.committee.name ] }

    @attendance = load_attendance
    @votes = @member.votes.joins(motion: :meeting).includes(motion: :meeting).order("meetings.starts_at DESC")
  end

  private

  def load_attendance
    records = @member.meeting_attendances
    return nil if records.none?

    total = records.count
    present = records.where(status: "present").count
    excused = records.where(status: "excused").count
    absent = records.where(status: "absent").count
    { total: total, present: present, excused: excused, absent: absent }
  end
end
