# frozen_string_literal: true

# POAM-017e (R9c) — dart-sass compiles the single stylesheet bundle; sprockets serves it.
#
# Load paths: dartsass-rails only looks in app/assets/stylesheets by default. The bundle
# also imports from vendor/assets/stylesheets (vendored widget css) and the bootstrap-sass
# gem (the one remaining gem-path import, accepted under POAM-017g).
#
# NB --quiet-deps silences the (expected, non-fatal) deprecation wall from inside
# bootstrap-sass 3.4.1 (slash-division, @import) — reviewed once during the R9c gate;
# our own stylesheets compile warning-free and their warnings stay visible.
Rails.application.config.dartsass.builds = {
  'application.scss' => 'application.css'
}

Rails.application.config.dartsass.build_options << '--load-path=vendor/assets/stylesheets'
Rails.application.config.dartsass.build_options <<
  "--load-path=#{Gem.loaded_specs['bootstrap-sass'].full_gem_path}/assets/stylesheets"
Rails.application.config.dartsass.build_options << '--quiet-deps'
