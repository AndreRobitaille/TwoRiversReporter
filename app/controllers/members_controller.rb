class MembersController < ApplicationController
  def index
    @members = Member.order(:name)
  end

  def show
    @member = Member.find(params[:id])
    @votes = @member.votes.joins(motion: :meeting).includes(motion: :meeting).order("meetings.starts_at DESC")
  end
end
