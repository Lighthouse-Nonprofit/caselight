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
Rails.application.config.dartsass.builds = {
  'application.scss' => 'application.css'
}

Rails.application.config.dartsass.build_options << '--load-path=vendor/assets/stylesheets'
Rails.application.config.dartsass.build_options << '--quiet-deps'
