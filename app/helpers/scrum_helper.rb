# Copyright © Emilio González Montaña
# Licence: Attribution & no derivates
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivates of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

module ScrumHelper

  include ProjectsHelper

  def render_hours(hours, options = {})
    if hours.nil?
      ""
    else
      if hours.is_a?(Integer)
        text = ("%d" % hours) unless options[:ignore_zero] and hours == 0
      elsif hours.is_a?(Float)
        text = ("%g" % hours) unless options[:ignore_zero] and hours == 0.0
      else
        text = hours unless options[:ignore_zero] and (hours.blank? or (hours == "0"))
      end
      unless text.blank?
        text = "#{text}h"
        unless options[:link].nil?
          text = link_to(text, options[:link])
        end
        render :inline => "<span title=\"#{options[:title]}\">#{text}</span>"
      end
    end
  end

  def render_pbi_left_header(pbi)
    parts = []
    if Scrum::Setting.render_position_on_pbi
      parts << "#{l(:field_position)}: #{pbi.position}"
    end
    if Scrum::Setting.render_category_on_pbi and pbi.category
      parts << "#{l(:field_category)}: #{h(pbi.category.name)}"
    end
    if Scrum::Setting.render_version_on_pbi and pbi.fixed_version
      parts << "#{l(:field_fixed_version)}: #{link_to_version(pbi.fixed_version)}"
    end
    render :inline => parts.join(", ")
  end

  def render_pbi_right_header(pbi)
    parts = []
    if Scrum::Setting.render_author_on_pbi
      parts << authoring(pbi.created_on, pbi.author)
    end
    if Scrum::Setting.render_updated_on_pbi and pbi.created_on != pbi.updated_on
      parts << "#{l(:label_updated_time, time_tag(pbi.updated_on))}"
    end
    render :inline => parts.join(", ")
  end

  def render_issue_icons(issue)
    icons = []
    if ((issue.is_pbi? and Scrum::Setting.render_pbis_speed) or
        (issue.is_task? and Scrum::Setting.render_tasks_speed))
      if (speed = issue.speed)
        if speed <= Scrum::Setting.lowest_speed
          icons << render_issue_icon(LOWEST_SPEED_ICON, speed)
        elsif speed <= Scrum::Setting.low_speed
          icons << render_issue_icon(LOW_SPEED_ICON, speed)
        elsif speed >= Scrum::Setting.high_speed
          icons << render_issue_icon(HIGH_SPEED_ICON, speed)
        end
      end
    end
    render :inline => icons.join('\n')
  end

  DEVIATION_ICONS = [LOWEST_SPEED_ICON = "icon-major-deviation",
                     LOW_SPEED_ICON = "icon-minor-deviation",
                     HIGH_SPEED_ICON = "icon-below-deviation"]

private

  def render_issue_icon(icon, speed)
    link_to("", "#", :class => "icon float-icon #{icon}",
            :title => l(:label_issue_speed, :speed => speed))
  end

end
