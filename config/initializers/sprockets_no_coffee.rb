# frozen_string_literal: true

# POAM-017e — CoffeeScript is retired: all sources were decaffeinated to ES2015+ and the
# coffee-script gems left the bundle. Sprockets 3 still registers its CoffeeScriptProcessor
# engine unconditionally (lib/sprockets.rb: `register_engine '.coffee', ...`), and computing
# the environment's processor cache keys eagerly autoloads the coffee-script gem — so with
# the gem gone, EVERY page that renders an asset tag raised
# `LoadError: cannot load such file -- coffee_script`, even with zero .coffee assets.
#
# Sprockets 3.x has no public unregister API for legacy engines, so neutralize the processor
# instead: a static cache_key (no gem probe) and a fail-loud call (nothing should ever reach
# it — spec/lib/coffee_removal_guard_spec.rb also forbids .coffee files at the source level).
#
# DELETE THIS SHIM with the Sprockets 4 upgrade (R10) — sprockets 4 dropped the built-in
# CoffeeScript engine.
require 'sprockets/coffee_script_processor'

module Sprockets
  module CoffeeScriptProcessor
    def self.cache_key
      @cache_key ||= "#{name}:retired-poam-017e:1"
    end

    def self.call(_input)
      raise 'CoffeeScript is retired (POAM-017e): a .coffee asset reached the pipeline. ' \
            'Convert it to plain JS — the compiler is no longer bundled.'
    end
  end
end
