module SubdomainHelper
  def with_subdomain(subdomain)
    subdomain = (subdomain || '')
    subdomain += '.' unless subdomain.empty?
    host = Rails.application.config.action_mailer.default_url_options[:host]
    [subdomain, host].join
  end

  def url_for(options = nil)
    # Rails 5 raises ("non-sanitized request parameters") when url_for is handed raw
    # ActionController::Parameters — which is what `url_for(params.merge(...))` in the
    # datagrid sort-link partials produces. Convert to a plain hash first; this is the
    # migration path Rails' own deprecation message points to (#to_unsafe_h). Every
    # view's url_for funnels through this override, so the fix is applied app-wide here.
    options = options.to_unsafe_h if options.is_a?(ActionController::Parameters)
    if options.is_a?(Hash) && options.key?(:subdomain)
      options[:host] = with_subdomain(options.delete(:subdomain))
    end
    super
  end
end
