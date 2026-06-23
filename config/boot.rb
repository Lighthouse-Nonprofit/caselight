ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../Gemfile', __FILE__)

require 'bundler/setup' # Set up gems listed in the Gemfile.

# concurrent-ruby 1.3.5+ stopped requiring Ruby's stdlib Logger, which Rails 7.0's
# ActiveSupport::LoggerThreadSafeLevel references at load -> "uninitialized constant Logger".
# Require it here in boot (loaded first by every entry point: bin/rails, rake, the server) so it
# is defined before activesupport loads. (Fixed upstream in Rails 7.1.)
require 'logger'
