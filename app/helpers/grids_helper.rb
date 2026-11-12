module GridsHelper
  def get_object_path(asset)
    return url_for([@client, asset]) if controller_name == 'progress_notes'
    url_for(asset)
  end
end
