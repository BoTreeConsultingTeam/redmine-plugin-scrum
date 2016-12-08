# Copyright © Emilio González Montaña
# Licence: Attribution & no derivates
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivates of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class ProductBacklogController < ApplicationController

  menu_item :product_backlog
  model_object Sprint

  before_filter :find_model_object,
                :only => [:show, :edit, :update, :destroy, :edit_effort, :update_effort, :burndown,
                          :release_plan, :stats, :sort]
  before_filter :find_project_from_association,
                :only => [:show, :edit, :update, :destroy, :edit_effort, :update_effort, :burndown,
                          :release_plan, :stats, :sort]
  before_filter :find_project_by_project_id,
                :only => [:index, :new, :create, :change_task_status, :burndown_index,
                          :stats_index]
  before_filter :check_issue_positions, :only => [:show]
  before_filter :authorize

  helper :scrum

  def index
    unless @project.product_backlogs.empty?
      redirect_to product_backlog_path(@project.product_backlogs.first)
    else
      render_error l(:error_no_sprints)
    end
  rescue
    render_404
  end

  def show
    unless @product_backlog.is_product_backlog?
      render_404
    end
  end

  def sort
    @product_backlog.pbis.each do |pbi|
      pbi.init_journal(User.current)
      pbi.position = params['pbi'].index(pbi.id.to_s) + 1
      pbi.check_bad_dependencies
      pbi.save!
    end
    render :nothing => true
  end

  def check_dependencies
    @pbis_dependencies = @product_backlog.get_dependencies
    respond_to do |format|
      format.js
    end
  end

  def new_pbi
    @pbi = Issue.new
    @pbi.project = @project
    @pbi.author = User.current
    @pbi.tracker = @project.trackers.find(params[:tracker_id])
    @pbi.sprint = @product_backlog
    respond_to do |format|
      format.html
      format.js
    end
  end

  def create_pbi
    begin
      @continue = !(params[:create_and_continue].nil?)
      @pbi = Issue.new(params[:issue])
      @pbi.project = @project
      @pbi.author = User.current
      @pbi.sprint = @product_backlog
      @pbi.save!
      @pbi.story_points = params[:issue][:story_points]
    rescue Exception => @exception
    end
    respond_to do |format|
      format.js
    end
  end

  def burndown
    @data = []
    @project.sprints.each do |sprint|
      @data << {:axis_label => sprint.name,
                :story_points => sprint.story_points.round(2),
                :pending_story_points => 0}
    end
    velocity_all_pbis, velocity_scheduled_pbis, @sprints_count = @project.story_points_per_sprint
    @velocity_type = params[:velocity_type] || 'only_scheduled'
    case @velocity_type
      when 'all'
        @velocity = velocity_all_pbis
      when 'only_scheduled'
        @velocity = velocity_scheduled_pbis
      else
        @velocity = params[:custom_velocity].to_f unless params[:custom_velocity].blank?
    end
    @velocity = 1.0 if @velocity.blank? or @velocity < 1.0
    pending_story_points = @product_backlog.story_points
    new_sprints = 1
    while pending_story_points > 0
      @data << {:axis_label => "#{l(:field_sprint)} +#{new_sprints}",
                :story_points => ((@velocity <= pending_story_points) ?
                    @velocity : pending_story_points).round(2),
                :pending_story_points => 0}
      pending_story_points -= @velocity
      new_sprints += 1
    end
    for i in 0..(@data.length - 1)
      others = @data[(i + 1)..(@data.length - 1)]
      @data[i][:pending_story_points] = (@data[i][:story_points] +
        (others.blank? ? 0 : others.collect{|other| other[:story_points]}.sum)).round(2)
      @data[i][:story_points_tooltip] = l(:label_pending_story_points,
                                          :pending_story_points => @data[i][:pending_story_points],
                                          :sprint => @data[i][:axis_label],
                                          :story_points => @data[i][:story_points])
    end
  end

  def release_plan
    @sprints = []
    velocity_all_pbis, velocity_scheduled_pbis, @sprints_count = @project.story_points_per_sprint
    @velocity_type = params[:velocity_type] || 'only_scheduled'
    case @velocity_type
      when 'all'
        @velocity = velocity_all_pbis
      when 'only_scheduled'
        @velocity = velocity_scheduled_pbis
      else
        @velocity = params[:custom_velocity].to_f unless params[:custom_velocity].blank?
    end
    @velocity = 1.0 if @velocity.blank? or @velocity < 1.0
    @total_story_points = 0.0
    @pbis_with_estimation = 0
    @pbis_without_estimation = 0
    versions = {}
    accumulated_story_points = @velocity
    current_sprint = {:pbis => [], :story_points => 0.0, :versions => []}
    @product_backlog.pbis.each do |pbi|
      if pbi.story_points
        @pbis_with_estimation += 1
        story_points = pbi.story_points.to_f
        @total_story_points += story_points
        while accumulated_story_points < story_points
          @sprints << current_sprint
          accumulated_story_points += @velocity
          current_sprint = {:pbis => [], :story_points => 0.0, :versions => []}
        end
        accumulated_story_points -= story_points
        current_sprint[:pbis] << pbi
        current_sprint[:story_points] += story_points
        if pbi.fixed_version
          versions[pbi.fixed_version.id] = {:version => pbi.fixed_version,
                                            :sprint => @sprints.count}
        end
      else
        @pbis_without_estimation += 1
      end
    end
    if current_sprint and (current_sprint[:pbis].count > 0)
      @sprints << current_sprint
    end
    versions.values.each do |info|
      @sprints[info[:sprint]][:versions] << info[:version]
    end
  end

private

  def check_issue_positions
    check_issue_position(Issue.where(:sprint_id => @product_backlog, :position => nil))
  end

  def check_issue_position(issue)
    if issue.is_a?(Issue)
      if issue.position.nil?
        issue.reset_positions_in_list
        issue.save!
        issue.reload
      end
    elsif issue.respond_to?(:each)
      issue.each do |i|
        check_issue_position(i)
      end
    else
      raise "Invalid type: #{issue.inspect}"
    end
  end

end
