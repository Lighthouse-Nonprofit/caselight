# Standard Rails 5+ abstract base model. The 4.2 -> 7.1 upgrade never added it (the app's models
# still inherit ActiveRecord::Base directly, which is fine). Added now because devise-security's
# OldPassword model inherits from ApplicationRecord. Existing models are unaffected.
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
