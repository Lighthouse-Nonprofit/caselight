# frozen_string_literal: true

# POAM-017e (R9c) — dart-sass compiles the single stylesheet bundle; sprockets serves it.
#
# Load paths: dartsass-rails only looks in app/assets/stylesheets by default. The bundle
# also imports from vendor/assets/stylesheets — the vendored widget css AND (POAM-017g flip)
# the vendored Bootstrap 5.3.8 SCSS under vendor/assets/stylesheets/bootstrap5/. The old
# bootstrap-sass gem load-path is gone with the gem.
#
# NB --quiet-deps silences the (expected, non-fatal) deprecation wall from inside the
# vendored Bootstrap 5.3 SCSS (colour-function / @import deprecations under dart-sass) —
# our own stylesheets compile warning-free and their warnings stay visible.
#
# --silence-deprecation=import: the bundle is @import-chained BY DESIGN — it mirrors the
# vendored Bootstrap 5 import stack (itself @import-based; a @use port is only meaningful
# when Bootstrap's SCSS moves). Silenced as a category so real deprecations (colour
# functions, division, etc.) in OUR files stay loud; revisit at dart-sass 3.0 / Bootstrap 6.
Rails.application.config.dartsass.builds = {
  'application.scss' => 'application.css'
}

Rails.application.config.dartsass.build_options << '--load-path=vendor/assets/stylesheets'
Rails.application.config.dartsass.build_options << '--quiet-deps'
Rails.application.config.dartsass.build_options << '--silence-deprecation=import'
