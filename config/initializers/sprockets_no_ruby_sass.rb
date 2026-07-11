# frozen_string_literal: true

# POAM-017e (R9c) — ruby-sass is retired: dart-sass (dartsass-rails) compiles
# application.scss into app/assets/builds/ and sprockets serves the built css.
#
# Same trap as the CoffeeScript retirement (sprockets_no_coffee.rb): sprockets 3 registers
# its Sass/Scss engines unconditionally and eagerly autoloads the `sass` gem when computing
# processor cache keys — with the gem gone, every asset-tag render would raise
# `LoadError: cannot load such file -- sass`. No unregister API in 3.x, so neutralize both
# processors: static cache keys, fail-loud call (no .sass/.scss should ever reach sprockets
# now — the only scss entrypoint is built by dart-sass before sprockets sees anything).
#
# DELETE THIS SHIM with the Sprockets 4 upgrade (R10) — sprockets 4 dropped the built-in
# sass engines.
require 'sprockets/sass_processor'

module Sprockets
  class SassProcessor
    def self.cache_key
      @cache_key ||= "#{name}:retired-poam-017e:1"
    end

    def self.call(_input)
      raise 'ruby-sass is retired (POAM-017e): a .sass/.scss asset reached sprockets. ' \
            'The stylesheet bundle is compiled by dart-sass (dartsass:build) into ' \
            'app/assets/builds/ — add new stylesheets to the application.scss import tree.'
    end
  end
end
