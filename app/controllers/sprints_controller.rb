# Copyright © Emilio González Montaña
# Licence: Attribution & no derivates
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivates of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class SprintsController < ApplicationController

  menu_item :sprint
  model_object Sprint

  before_filter :find_model_object,
                :only => [:show, :edit, :update, :destroy, :edit_effort, :update_effort, :burndown,
                          :stats, :sort]
  before_filter :find_project_from_association,
                :only => [:show, :edit, :update, :destroy, :edit_effort, :update_effort, :burndown,
                          :stats, :sort]
  before_filter :find_project_by_project_id,
                :only => [:index, :new, :create, :change_task_status, :burndown_index,
                          :stats_index]
  before_filter :find_pbis, :only => [:sort]
  before_filter :authorize

  helper :custom_fields
  helper :scrum
  helper :timelog

  def index
    if (current_sprint = @project.current_sprint)
      redirect_to sprint_path(current_sprint)
    else
      render_error l(:error_no_sprints)
    end
  rescue
    render_404
  end

  def show
    redirect_to project_product_backlog_index_path(@project) if @sprint.is_product_backlog?
  end

  def new
    @sprint = Sprint.new(:project => @project, :is_product_backlog => params[:create_product_backlog])
    if @sprint.is_product_backlog
      @sprint.name = l(:label_product_backlog)
      @sprint.sprint_start_date = @sprint.sprint_end_date = Date.today
    end
  end

  def create
    @sprint = Sprint.new(:user => User.current,
                         :project => @project,
                         :is_product_backlog => (!(params[:create_product_backlog].nil?)))
    @sprint.safe_attributes = params[:sprint]
    if request.post? and @sprint.save
      if params[:create_product_backlog]
        @project.product_backlogs << @sprint
        raise 'Fail to update project with product backlog' unless @project.save!
      end
      flash[:notice] = l(:notice_successful_create)
      redirect_back_or_default settings_project_path(@project, :tab => 'sprints')
    else
      render :action => :new
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def edit
  end

  def update
    @sprint.safe_attributes = params[:sprint]
    if @sprint.save
      flash[:notice] = l(:notice_successful_update)
      redirect_back_or_default settings_project_path(@project, :tab => 'sprints')
    else
      render :action => :edit
    end
  end

  def destroy
    if @sprint.issues.any?
      flash[:error] = l(:notice_sprint_has_issues)
    else
      @sprint.destroy
    end
  rescue
    flash[:error] = l(:notice_unable_delete_sprint)
  ensure
    redirect_to settings_project_path(@project, :tab => 'sprints')
  end

  def change_task_status
    @issue = Issue.find(params[:task].match(/^task_(\d+)$/)[1].to_i)
    @old_status = @issue.status
    @issue.init_journal(User.current)
    @issue.status = IssueStatus.find(params[:status].to_i)
    raise 'New status is not allowed' unless @issue.new_statuses_allowed_to.include?(@issue.status)
    @issue.save!
    respond_to do |format|
      format.js { render 'scrum/update_task' }
    end
  end

  def edit_effort
  end

  def update_effort
    params[:user].each_pair do |user_id, days|
      user_id = user_id.to_i
      days.each_pair do |day, effort|
        day = day.to_i
        date = @sprint.sprint_start_date + day.to_i
        sprint_effort = SprintEffort.where(:sprint_id => @sprint.id,
                                           :user_id => user_id,
                                           :date => date).first
        if sprint_effort.nil?
          unless effort.blank?
            sprint_effort = SprintEffort.new(:sprint_id => @sprint.id,
                                             :user_id => user_id,
                                             :date => @sprint.sprint_start_date + day,
                                             :effort => effort)
          end
        elsif effort.blank?
          sprint_effort.destroy
          sprint_effort = nil
        else
          sprint_effort.effort = effort
        end
        sprint_effort.save! unless sprint_effort.nil?
      end
    end
    flash[:notice] = l(:notice_successful_update)
    redirect_back_or_default settings_project_path(@project, :tab => 'sprints')
  end

  def burndown_index
    if @project.last_sprint
      redirect_to burndown_sprint_path(@project.last_sprint, :type => params[:type])
    else
      render_error l(:error_no_sprints)
    end
  rescue Exception => exception
    render_404
  end

  def burndown
    if params[:type] == 'sps'
      @data = []
      @sprint.completed_sps_by_day.each do |date, sps|
        date_label = "#{I18n.l(date, :format => :scrum_day)} #{date.day}"
        @data << {:day => date,
                  :axis_label => date_label,
                  :pending_sps => sps,
                  :pending_sps_tooltip => l(:label_pending_sps_tooltip,
                                            :date => date_label,
                                            :sps => sps)}
      end
      @data.last[:axis_label] = l(:label_end)
      @data.last[:pending_sps_tooltip] = l(:label_pending_sps_tooltip,
                                           :date => l(:label_end),
                                           :sps => 0)
      @type = :sps
    else
      @data = []
      last_pending_effort = @sprint.estimated_hours
      last_day = nil
      ((@sprint.sprint_start_date)..(@sprint.sprint_end_date)).each do |date|
        if @sprint.efforts.where(['date = ?', date]).count > 0
          efforts = @sprint.efforts.where(['date >= ?', date])
          estimated_effort = efforts.collect{|effort| effort.effort}.compact.sum
          if date <= Date.today
            efforts = []
            @sprint.issues.each do |issue|
              if issue.use_in_burndown?
                efforts << issue.pending_efforts.where(['date <= ?', date]).last
              end
            end
            pending_effort = efforts.compact.collect{|effort| effort.effort}.compact.sum
          end
          date_label = "#{I18n.l(date, :format => :scrum_day)} #{date.day}"
          @data << {:day => date,
                    :axis_label => date_label,
                    :estimated_effort => estimated_effort,
                    :estimated_effort_tooltip => l(:label_estimated_effort_tooltip,
                                                   :date => date_label,
                                                   :hours => estimated_effort),
                    :pending_effort => last_pending_effort,
                    :pending_effort_tooltip => l(:label_pending_effort_tooltip,
                                                 :date => date_label,
                                                 :hours => last_pending_effort)}
          last_pending_effort = pending_effort
          last_day = date.day
        end
      end
      @data << {:day => last_day,
                :axis_label => l(:label_end),
                :estimated_effort => 0,
                :estimated_effort_tooltip => l(:label_estimated_effort_tooltip,
                                               :date => l(:label_end),
                                               :hours => 0),
                :pending_effort => last_pending_effort,
                :pending_effort_tooltip => l(:label_pending_effort_tooltip,
                                             :date => l(:label_end),
                                             :hours => last_pending_effort)}
      @type = :effort
    end
  end

  def stats_index
    if @project.last_sprint
      redirect_to stats_sprint_path(@project.last_sprint)
    else
      render_error l(:error_no_sprints)
    end
  rescue
    render_404
  end

  def stats
    @days = []
    @members_efforts = {}
    @estimated_efforts_totals = {:days => {}, :total => 0.0}
    @done_efforts_totals = {:days => {}, :total => 0.0}
    ((@sprint.sprint_start_date)..(@sprint.sprint_end_date)).each do |date|
      if @sprint.efforts.where(['date = ?', date]).count > 0
        @days << {:date => date, :label => "#{I18n.l(date, :format => :scrum_day)} #{date.day}"}
        if User.current.allowed_to?(:view_sprint_stats_by_member, @project)
          estimated_effort_conditions = ['date = ?', date]
          done_effort_conditions = ['spent_on = ?', date]
        else
          estimated_effort_conditions = ['date = ? AND user_id = ?', date, User.current.id]
          done_effort_conditions = ['spent_on = ? AND user_id = ?', date, User.current.id]
        end
        @sprint.efforts.where(estimated_effort_conditions).each do |sprint_effort|
          if sprint_effort.effort
            init_members_efforts(@members_efforts, sprint_effort.user)
            member_estimated_efforts_days = init_member_efforts_days(@members_efforts,
                                                                     @sprint,
                                                                     sprint_effort.user,
                                                                     date,
                                                                     true)
            member_estimated_efforts_days[date] += sprint_effort.effort
            @members_efforts[sprint_effort.user.id][:estimated_efforts][:total] += sprint_effort.effort
            @estimated_efforts_totals[:days][date] = 0.0 unless @estimated_efforts_totals[:days].include?(date)
            @estimated_efforts_totals[:days][date] += sprint_effort.effort
            @estimated_efforts_totals[:total] += sprint_effort.effort
          end
        end
        @project.time_entries.where(done_effort_conditions).each do |time_entry|
          if time_entry.hours
            init_members_efforts(@members_efforts,
                                 time_entry.user)
            member_done_efforts_days = init_member_efforts_days(@members_efforts,
                                                                @sprint,
                                                                time_entry.user,
                                                                date,
                                                                false)
            member_done_efforts_days[date] += time_entry.hours
            @members_efforts[time_entry.user.id][:done_efforts][:total] += time_entry.hours
            @done_efforts_totals[:days][date] = 0.0 unless @done_efforts_totals[:days].include?(date)
            @done_efforts_totals[:days][date] += time_entry.hours
            @done_efforts_totals[:total] += time_entry.hours
          end
        end
      end
    end
    @members_efforts = @members_efforts.values.sort{|a, b| a[:member] <=> b[:member]}

    @sps_by_pbi_category, @sps_by_pbi_category_total = @sprint.sps_by_pbi_category

    @sps_by_pbi_type, @sps_by_pbi_type_total = @sprint.sps_by_pbi_type

    @sps_by_pbi_creation_date, @sps_by_pbi_creation_date_total = @sprint.sps_by_pbi_creation_date

    @effort_by_activity, @effort_by_activity_total = @sprint.time_entries_by_activity

    if User.current.allowed_to?(:view_sprint_stats_by_member, @project)
      @efforts_by_member_and_activity = @sprint.efforts_by_member_and_activity
      @efforts_by_member_and_activity_chart = {:id => 'stats_efforts_by_member_and_activity', :height => 400}
    end
  end

  def sort
    new_pbis_order = []
    params.keys.each do |param|
      id = param.scan(/pbi\_(\d+)/)
      new_pbis_order << id[0][0].to_i if id and id[0] and id[0][0]
    end
    @pbis.each do |pbi|
      if (index = new_pbis_order.index(pbi.id))
        pbi.position = index + 1
        pbi.save!
      end
    end
    render :nothing => true
  end

private

  def init_members_efforts(members_efforts, member)
    unless members_efforts.include?(member.id)
      members_efforts[member.id] = {
        :member => member,
        :estimated_efforts => {
          :days => {},
          :total => 0.0
        },
        :done_efforts => {
          :days => {},
          :total => 0.0
        }
      }
    end
  end

  def init_member_efforts_days(members_efforts, sprint, member, date, estimated)
    member_efforts_days = members_efforts[member.id][estimated ? :estimated_efforts : :done_efforts][:days]
    unless member_efforts_days.include?(date)
      member_efforts_days[date] = 0.0
    end
    return member_efforts_days
  end

  def find_pbis
    @pbis = @sprint.pbis
  rescue
    render_404
  end

end
