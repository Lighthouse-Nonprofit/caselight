module ProgramStreamHelper
  def html_column(full_width)
    full_width ? '' : 'col-md-6'
  end

  def delete_button(program)
    if program.client_enrollments.present?
      content_tag(:div, '', class: 'btn btn-outline btn-danger btn-xs disabled', 'aria-disabled': 'true') do
        fa_icon('trash', 'aria-hidden': true)
      end
    else
      link_to program_stream_path(program), method: 'delete',  data: { confirm: t('.are_you_sure') }, class: 'btn btn-outline btn-danger btn-xs', 'aria-label': t('shared.actions.delete', default: 'Delete') do
        fa_icon('trash', 'aria-hidden': true)
      end
    end
  end

  def program_stream_redirect_path
    params[:client] == 'true' ? request.referer : program_streams_path
  end

  def disable_rules_is_used(object)
    if object.is_used?
      "hide-tracking-form"
    end
  end
end