class ClientHistory
  include Mongoid::Document
  include Mongoid::Timestamps

  default_scope { where(tenant: Organization.current.try(:short_name)) }

  field :object, type: Hash
  field :tenant, type: String, default: ->{ Organization.current.short_name }

  embeds_many :agency_client_histories
  embeds_many :case_client_histories
  embeds_many :case_worker_client_histories
  embeds_many :client_custom_field_property_histories
  embeds_many :client_family_histories
  embeds_many :client_quantitative_case_histories

  after_save :create_agency_client_history, if: -> { object.key?("agency_ids") }
  after_save :create_case_worker_client_history, if: -> { object.key?("user_ids") }
  after_save :create_client_quantitative_case_history, if: -> { object.key?("quantitative_case_ids") }
  after_save :create_case_client_history,   if: -> { object.key?("case_ids") }
  after_save :create_client_family_history, if: -> { object.key?("family_ids") }
  after_save :create_client_custom_field_property_history, if: -> { object.key?("custom_field_property_ids") }

  def self.initial(client)
    # Reload a fresh instance: on Rails 5, has_many :through caches (client.family_ids,
    # case_ids, etc.) can be stale-empty when this runs inside an after_save, so the history
    # would omit them. A fresh load queries the current associations.
    client = Client.find(client.id)
    # Phase 6 (SC-28 / POAM-SC28-HIST): `attributes` returns DECRYPTED values for the encrypted
    # columns — scrub them (and every embedded snapshot below) so the shared Mongo history stops
    # being a plaintext PII shadow of the encrypted Postgres columns. Ids/statuses/dates survive.
    attributes = HistoryPiiFilter.scrub(Client, client.attributes)
    attributes = attributes.merge('quantitative_case_ids' => client.quantitative_case_ids) if client.quantitative_case_ids.any?
    attributes = attributes.merge('agency_ids' => client.agency_ids) if client.agency_ids.any?
    attributes = attributes.merge('case_ids' => client.case_ids) if client.case_ids.any?
    attributes = attributes.merge('family_ids' => client.family_ids) if client.family_ids.any?
    attributes = attributes.merge('custom_field_property_ids' => client.custom_field_properties.ids) if client.custom_field_properties.any?
    attributes = attributes.merge('user_ids' => client.user_ids) if client.user_ids.any?
    create(object: attributes)
  end

  private

  # Every embedded snapshot below routes through HistoryPiiFilter.scrub — a no-op for models with
  # no encrypted attributes (Agency/Case/QuantitativeCase today), load-bearing for User/Family/
  # CustomFieldProperty. try(:attributes) may be nil (record since deleted); scrub passes nil through.

  def create_client_quantitative_case_history
    object['quantitative_case_ids'].each do |quantitative_case_id|
      quantitative_case = HistoryPiiFilter.scrub(QuantitativeCase, QuantitativeCase.find_by(id: quantitative_case_id).try(:attributes))
      client_quantitative_case_histories.create(object: quantitative_case)
    end
  end

  def create_agency_client_history
    object['agency_ids'].each do |agency_id|
      agency = HistoryPiiFilter.scrub(Agency, Agency.find_by(id: agency_id).try(:attributes))
      agency_client_histories.create(object: agency)
    end
  end

  def create_case_client_history
    object['case_ids'].each do |case_id|
      c_case = HistoryPiiFilter.scrub(Case, Case.find_by(id: case_id).try(:attributes))
      case_client_histories.create(object: c_case)
    end
  end

  def create_case_worker_client_history
    # Phase 6: the staff snapshot used to carry the full User attribute hash — email, names, mobile,
    # password hash, OTP secret, sign-in IPs. The scrub removes all of it (EXTRA_DENYLIST covers the
    # credential/IP columns); the old IP-stringify lines are gone because they would re-add the keys
    # as "" after the scrub.
    object['user_ids'].each do |user_id|
      case_worker = HistoryPiiFilter.scrub(User, User.find_by(id: user_id).try(:attributes))
      case_worker_client_histories.create(object: case_worker)
    end
  end

  def create_client_custom_field_property_history
    object['custom_field_property_ids'].each do |ccfp_id|
      custom_field_property = HistoryPiiFilter.scrub(CustomFieldProperty, CustomFieldProperty.find_by(id: ccfp_id).try(:attributes))
      # Post-scrub the Tier-5 encrypted `properties` values are absent; format only what remains
      # (nil-guard keeps the legacy label-normalization from raising inside an after_save).
      if custom_field_property.is_a?(Hash) && custom_field_property['properties'].present?
        custom_field_property['properties'] = format_custom_field_property(custom_field_property)
      end
      client_custom_field_property_histories.create(object: custom_field_property)
    end
  end

  def create_client_family_history
    object['family_ids'].each do |family_id|
      family = HistoryPiiFilter.scrub(Family, Family.find_by(id: family_id).try(:attributes))
      client_family_histories.create(object: family)
    end
  end

  def format_custom_field_property(custom_field_property)
    mappings = {}
    custom_field_property['properties'].each do |k, v|
      mappings[k] = k.gsub(/(\s|[.])/, '_')
    end
    custom_field_property['properties'].map {|k, v| [mappings[k].downcase, v] }.to_h
  end
end
