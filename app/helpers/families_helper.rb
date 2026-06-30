module FamiliesHelper
  def family_member_list(object)
    html_tags = []

    if params[:locale] == 'km'
      html_tags << "#{I18n.t('datagrid.columns.families.female_children_count')} : #{object.female_children_count.to_i}"
      html_tags << "#{I18n.t('datagrid.columns.families.male_children_count')} : #{object.male_children_count.to_i}"
      html_tags << "#{I18n.t('datagrid.columns.families.female_adult_count')} : #{object.female_adult_count.to_i}"
      html_tags << "#{I18n.t('datagrid.columns.families.male_adult_count')} : #{object.male_adult_count.to_i}"
    elsif params[:locale] == 'en'
      html_tags << "#{I18n.t('datagrid.columns.families.female')} #{'child'.pluralize(object.female_children_count.to_i)} : #{object.female_children_count.to_i}"
      html_tags << "#{I18n.t('datagrid.columns.families.male')} #{'child'.pluralize(object.male_children_count.to_i)} : #{object.male_children_count.to_i}"
      html_tags << "#{I18n.t('datagrid.columns.families.female')} #{'adult'.pluralize(object.female_adult_count.to_i)}  : #{object.female_adult_count.to_i}"
      html_tags << "#{I18n.t('datagrid.columns.families.male')} #{'adult'.pluralize(object.male_adult_count.to_i)} : #{object.male_adult_count.to_i}"
    end

    content_tag(:ul, safe_join(html_tags.map { |html_tag| content_tag(:li, html_tag) }), class: 'family-members-list')
  end

  def family_clients_list(object)
    clients = object.cases.non_emergency.active.map(&:client)
    content_tag(:ul, safe_join(clients.map { |client| content_tag(:li, link_to(entity_name(client), client_path(client))) }), class: 'family-clients-list')
  end

  def family_workers_list(object)
    user_ids = Client.joins(:cases).where(cases: { id: object.ids }).joins(:case_worker_clients).map(&:user_ids).flatten.uniq
    content_tag(:ul, safe_join(User.where(id: user_ids).map { |user| content_tag(:li, link_to(entity_name(user), user_path(user))) }), class: 'family-clients-list')
  end

  def family_workers_count(object)
    Client.joins(:cases).where(cases: { id: object.ids }).joins(:case_worker_clients).map(&:user_ids).flatten.uniq.size
  end

  def family_case_history(object)
    if object.case_history =~ /\A#{URI::regexp(['http', 'https'])}\z/
      link_to object.case_history, object.case_history, class: 'case-history', target: :_blank
    else
      object.case_history
    end
  end
end
