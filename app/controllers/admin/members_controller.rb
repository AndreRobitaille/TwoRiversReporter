module Admin
  class MembersController < BaseController
    before_action :set_member, only: %i[show create_alias destroy_alias merge]

    def index
      @members = Member.left_joins(:member_aliases, :votes, :committee_memberships)
                       .select(
                         "members.*",
                         "COUNT(DISTINCT member_aliases.id) AS alias_count",
                         "COUNT(DISTINCT votes.id) AS vote_count",
                         "COUNT(DISTINCT committee_memberships.id) AS membership_count"
                       )
                       .group("members.id")
                       .order(:name)
    end

    def show
      @aliases = @member.member_aliases.order(:name)
      @memberships = @member.committee_memberships.includes(:committee).order(ended_on: :desc, started_on: :desc)
      @attendances = @member.meeting_attendances.includes(:meeting).order("meetings.starts_at DESC").limit(20)
      @votes = @member.votes.joins(motion: :meeting).includes(motion: :meeting).order("meetings.starts_at DESC").limit(20)
      @other_members = Member.where.not(id: @member.id).order(:name)
    end

    def create_alias
      @alias = @member.member_aliases.build(name: params[:name])

      if @alias.save
        redirect_to admin_member_path(@member), notice: "Alias added."
      else
        redirect_to admin_member_path(@member), alert: "Failed: #{@alias.errors.full_messages.join(', ')}"
      end
    end

    def destroy_alias
      alias_record = @member.member_aliases.find(params[:alias_id])
      alias_record.destroy
      redirect_to admin_member_path(@member), notice: "Alias removed."
    end

    def merge
      target = Member.find(params[:target_member_id])
      @member.merge_into!(target)
      redirect_to admin_member_path(target), notice: "#{@member.name} merged into #{target.name}."
    rescue ArgumentError => e
      redirect_to admin_member_path(@member), alert: e.message
    end

    private

    def set_member
      @member = Member.find(params[:id])
    end
  end
end
