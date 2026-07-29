module AttachmentHelper
  def original_filename(object)
    file_name = File.basename(object.file.path).split('.').first.titleize
    extention = File.basename(object.file.path).split('.').last
    "#{file_name}.#{extention}"
  end

  def original_filetype(object)
    object.file.content_type.split('/')
  end

  def preview_or_download(object)
    return t('.preview_download') if pdf?(object) || image?(object)
    t('.download')
  end

  def target_blank(object)
    return '_blank' if pdf?(object) || image?(object)
  end

  # POAM-019 (PR B3) — companion pair for the verified-PDF inline path. Every
  # authorized_download link site passes BOTH:
  #   * inline_view_params merges `disposition=inline` into the download URL for PDFs — a HINT
  #     only: DownloadsController re-verifies (extension + %PDF- magic) and silently falls back
  #     to attachment, so a mislabeled file can never ride this into an inline serve.
  #   * noopener_for pairs rel=noopener with every target_blank tab (the new tab must not hold
  #     a handle back to the case-file window).
  # Phase 6 forced attachment-disposition on all file mounts, which silently broke the
  # "Preview" intent of preview_or_download for PDFs — this restores it through the gated path.
  def inline_view_params(object)
    pdf?(object) ? { disposition: 'inline' } : {}
  end

  def noopener_for(object)
    'noopener' if target_blank(object)
  end

  private

  def pdf?(object)
    original_filetype(object).last == 'pdf'
  end

  def image?(object)
    original_filetype(object).first == 'image'
  end
end
