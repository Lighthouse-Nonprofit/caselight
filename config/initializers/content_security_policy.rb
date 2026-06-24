# Content Security Policy — FedRAMP SC-7 / SI-10, SOC 2 CC6.6 / CC6.8.
#
# Started in REPORT-ONLY. The app still ships inline <script> and inline styles, and a few views
# eval() stringified data (tracked as POAM-004), so an *enforced* policy would break pages today.
# Report-only emits the policy as Content-Security-Policy-Report-Only: the browser evaluates it and
# would report violations but blocks nothing. This lets us:
#   1. ship a documented baseline CSP now (auditable control), and
#   2. tighten toward an enforced, nonce-based policy in a later pass — drop :unsafe_inline /
#      :unsafe_eval, add per-request nonces, wire a report_uri, then flip report_only -> false.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.base_uri        :self
    policy.object_src      :none
    policy.frame_ancestors :self
    # :unsafe_inline / :unsafe_eval are required by the current (un-refactored) front-end; they are
    # the reason this policy ships report-only rather than enforced.
    policy.script_src      :self, :https, :unsafe_inline, :unsafe_eval
    policy.style_src       :self, :https, :unsafe_inline
    policy.img_src         :self, :https, :data
    policy.font_src        :self, :https, :data
    policy.connect_src     :self, :https
  end

  # Observe-only for now (blocks nothing). Flip to false to enforce once the front-end is CSP-clean.
  config.content_security_policy_report_only = true
end
