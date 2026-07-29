module AdvancedSearches
  # Phase 4 Tier 5 (FedRAMP SC-28, SOC 2 C1.1) — shared IN-RUBY decrypt-and-filter engine for the four
  # `.properties` advanced-search builders (ClientCustomFormSqlBuilder, EnrollmentSqlBuilder,
  # TrackingSqlBuilder, ExitProgramSqlBuilder).
  #
  # WHY: those builders used to push raw JSONB operators (`->`, `->>`, `?`, ILIKE, ::int casts) into
  # Postgres against the `properties` jsonb column. Tier 5 encrypts that column NON-DETERMINISTICALLY: the
  # raw bytes are now a ciphertext envelope STRING, and `record.properties` is only a Hash AFTER the
  # encrypted `attribute :json` type decrypts it in Ruby. Postgres can no longer see inside it, so the
  # JSONB SQL is impossible. We LOAD the candidate records (same scope as before), read each decrypted
  # `.properties` Hash, and re-apply the SAME operator semantics in Ruby — returning the SAME matched ids
  # the SQL would have. Each builder keeps its { id: '<table>.id IN (?)', values: [ids] } contract, so
  # ClientBaseSqlBuilder / ClientAdvancedSearch are UNCHANGED.
  #
  # PERFORMANCE — FLAG (mirrors the Tier 2/3 caveat density): this is O(n)-decrypt — one AES-GCM decrypt
  # per candidate row in the builder's scope, vs the old single indexed JSONB query. ACCEPTABLE at the
  # pilot's volume (a handful of staff, synthetic data, low hundreds of rows). It will NOT scale to the
  # real-data host: a custom-form search there should move to a queryable design (a deterministic
  # blind-index sidecar per searchable field, or a decrypted materialized search table refreshed out of
  # band). Do NOT ship this rewrite to production volume without that follow-up.
  # Ledgered 2026-07-26 as POAM-024 (docs/compliance/vulnerability-poam.md) — a pre-real-data gate.
  #
  # SEMANTICS REPRODUCED (1:1 with the old SQL — VERIFIED against a live Postgres oracle in caselight-app-1):
  #   * equal/not_equal  <- `properties -> 'f' ? 'v'` (jsonb `?` = string-key/element membership):
  #       equal matches when the value is the scalar 'v' OR (for checkbox/multi-select arrays) 'v' is an
  #       element. Reproduced as member?(raw, v).
  #       not_equal is the SQL `where.not(-> 'f' ? 'v')`. CRITICAL: the `?` operator on a MISSING key
  #       yields SQL NULL, and `WHERE NOT NULL` is falsy => the row is EXCLUDED. Oracle confirmed: over
  #       rows {k:v},{k:other},{other:x},{k:''},{k:[v,x]}, `NOT (p->'k' ? 'v')` => {2,4} (the missing-key
  #       row is DROPPED). So not_equal must require the key be PRESENT: present? && !member?. (The earlier
  #       draft kept missing-key rows — that was a silent-wrong-result bug; fixed here.)
  #   * contains/not_contains <- `->> 'f' ILIKE '%v%'`: case-insensitive substring on the TEXT form of the
  #       value. `->>` renders a jsonb array as its JSON text WITH a space after the comma (oracle:
  #       ["v", "x"]); text_form reproduces that spacing exactly. not_contains is NULL-propagating: a
  #       missing/NULL value yields NULL (row EXCLUDED), matching `NOT ILIKE` on NULL (oracle: {2} only).
  #   * less/less_or_equal/greater/greater_or_equal/between <- ordered compare with the old `... != ''`
  #       guard (skip blank values). NUMERIC iff type=='integer' (the only type the builders cast ::int):
  #       coerce both sides with Float() and skip non-numeric/blank rows. NB the old SQL ::int RAISED on a
  #       non-numeric string; Float()+skip is strictly more robust (only ever EXCLUDES junk the indexed
  #       query would also have failed) — a flagged, intentional refinement, also accepts decimals. Else
  #       STRING (lexicographic) compare — which reproduces date fields (type 'date', stored 'yyyy-mm-dd'
  #       so lexicographic == chronological).
  #   * is_empty/is_not_empty <- `-> 'f' ? ''`: the value is the empty string '' (or '' is an array
  #       element). is_empty = member?(raw, ''). is_not_empty = present-key && !member?(raw, '') — same
  #       missing-key EXCLUSION as not_equal (oracle: `NOT (p->'k' ? '')` => {1,2,5}, missing-key DROPPED).
  #
  # @field is the RAW property key (already the last `_`-segment, UN-escaped). There is no SQL string
  # interpolation anymore, so the builders' old gsub("'","''") quote-doubling is NOT applied — the key is
  # compared as a literal Hash key, so callers pass the raw key (doubling a quote would corrupt it).
  class PropertiesFilter
    NUMERIC_ORDER_OPERATORS = %w[less less_or_equal greater greater_or_equal between].freeze

    # field    : String property key to look up in each record's decrypted .properties Hash
    # operator : one of the advanced-search operators below
    # value    : scalar String, or [first, last] Array for `between`
    # type     : rule field type ('integer' triggers numeric coercion; anything else => string compare).
    #            Pass nil to reproduce ExitProgramSqlBuilder's no-@type (always-text) legacy behaviour.
    def initialize(field:, operator:, value:, type:)
      @field    = field
      @operator = operator
      @value    = value
      @type     = type
    end

    # records : an Enumerable of model instances already scoped as the builder scopes them today
    #           (decrypted .properties available). Returns the subset whose .properties matches.
    # This remains the LEGACY/RESIDUAL engine — #apply below is the POAM-024 read path.
    def select(records)
      records.select { |record| match?(record.properties) }
    end

    # ------------------------------------------------------------------------------------------------
    # POAM-024 (PR A3) — the sidecar read path. Takes the builder's RELATION and returns a RELATION
    # (same scope narrowed to matching rows), so the builders keep their joins and project client ids
    # with a pluck instead of instantiating records. Mode comes from config.x.tier5_sidecar_search
    # (config/initializers/tier5_sidecar_search.rb): off = legacy only; shadow (default) = serve
    # legacy, compare against the sidecar and log a VALUES-FREE tier5_sidecar_shadow AccessLog event
    # on divergence; on = sidecar-served.
    #
    # Operator strategy (matches the ledger design):
    #   * equality family (equal / not_equal / is_empty / is_not_empty) -> pure indexed SQL against
    #     the entry table. The deterministic `where(value: ...)` probe rides
    #     ExtendedDeterministicQueries (current + previous schemes), like the Tier-3/4 name scopes.
    #     not_equal / is_not_empty = presence-EXISTS AND NOT value-EXISTS — reproducing the oracle's
    #     missing-key EXCLUSION (a NOT IN over an empty subquery is TRUE, so present-key rows with no
    #     matching element pass; missing-key rows fail the presence side).
    #   * contains / not_contains / ordered / between -> presence-prefiltered Ruby: every residual
    #     operator requires the key to be present (contains: !txt.nil?; ordered: the != '' guard),
    #     so "ids with >=1 entry row for the label" is a GUARANTEED SUPERSET of the matches; the
    #     candidates then run through the SAME oracle-verified #match? — byte-identical semantics by
    #     construction. No candidate cap (a cap = silent wrong results); volume is logged upstream.
    #
    # Known accepted micro-divergence (also in PropertiesSearchable's header): member?'s degenerate
    # whole-array `raw.to_s == value.to_s` branch (equal probing the literal Ruby rendering of an
    # array) has no element-row representation. The shadow phase exists to prove it never fires.
    # ------------------------------------------------------------------------------------------------
    EQUALITY_OPERATORS = %w[equal not_equal is_empty is_not_empty].freeze

    def apply(relation)
      case sidecar_mode
      when :on     then sidecar_apply(relation)
      when :shadow then shadow_apply(relation)
      else              legacy_apply(relation)
      end
    end

    private

    def sidecar_mode
      Rails.application.config.x.tier5_sidecar_search || :shadow
    end

    def legacy_apply(relation)
      relation.where(id: select(relation).map(&:id))
    end

    def sidecar_apply(relation)
      if EQUALITY_OPERATORS.include?(@operator)
        equality_sql(relation)
      else
        residual_apply(relation)
      end
    end

    # Serve legacy, race the sidecar, log divergence. SELF-RESCUING: a sidecar failure must never
    # break search while shadowing (AuthorizationShadow contract) — it logs and falls through.
    def shadow_apply(relation)
      legacy_ids = select(relation).map(&:id)
      begin
        sidecar_ids = sidecar_apply(relation).pluck(:id)
        if legacy_ids.to_set != sidecar_ids.to_set
          AccessLog.system_event!(
            event_type: 'tier5_sidecar_shadow',
            metadata:   {
              # VALUES-FREE by design: model / operator / type / counts. Never the field label,
              # never the probed value, never matched ids.
              owner_model:   relation.klass.name,
              operator:      @operator,
              field_type:    @type,
              legacy_count:  legacy_ids.size,
              sidecar_count: sidecar_ids.size,
              diff_count:    (legacy_ids.to_set ^ sidecar_ids.to_set).size
            }
          )
        end
      rescue => e
        Rails.logger.warn("[tier5_sidecar_shadow] comparison failed: #{e.class}: #{e.message}")
      end
      relation.where(id: legacy_ids)
    end

    def entry_class_for(relation)
      relation.klass.properties_search_entry_class
    end

    def entry_fk_for(relation)
      relation.klass.properties_search_entry_foreign_key
    end

    def equality_sql(relation)
      entries  = entry_class_for(relation)
      fk       = entry_fk_for(relation)
      presence = entries.where(field_label: @field).select(fk)
      probe    = ->(v) { entries.where(field_label: @field, value: v).select(fk) }

      case @operator
      when 'equal'        then relation.where(id: probe.call(@value.to_s))
      when 'is_empty'     then relation.where(id: probe.call(''))
      when 'not_equal'    then relation.where(id: presence).where.not(id: probe.call(@value.to_s))
      when 'is_not_empty' then relation.where(id: presence).where.not(id: probe.call(''))
      end
    end

    def residual_apply(relation)
      entries    = entry_class_for(relation)
      fk         = entry_fk_for(relation)
      candidates = relation.where(id: entries.where(field_label: @field).select(fk))

      matched_ids = []
      candidates.find_each(batch_size: 500) do |record|
        matched_ids << record.id if match?(record.properties)
      end
      relation.where(id: matched_ids)
    end

    def integer?
      @type == 'integer'
    end

    # The TEXT rendering of a jsonb value as Postgres `->>` produces it. For a scalar string `->>` returns
    # the bare string; for a jsonb array it returns the JSON text WITH a space after each comma
    # (oracle-confirmed: ["v", "x"]). The custom forms store scalar fields as plain strings and checkbox
    # groups as arrays, so reproduce both — matching Postgres spacing so contains/not_contains over a
    # multi-select array is byte-identical to the legacy ILIKE.
    def text_form(raw)
      case raw
      when nil    then nil
      when String then raw
      when Array  then '[' + raw.map { |e| e.to_json }.join(', ') + ']'
      when Hash   then raw.to_json
      else raw.to_s
      end
    end

    # jsonb `?` membership: true when `value` equals the scalar string, OR is an element of the array.
    # A MISSING/NULL value matches NOTHING: Postgres `-> 'f' ? 'v'` on a missing key is NULL (falsy in
    # WHERE), and crucially `nil.to_s == ''` would otherwise make `is_empty`/equal-'' spuriously match a
    # missing-key row. Guarding nil here keeps equal / is_empty / not_equal / is_not_empty all faithful to
    # the SQL (the not_equal/is_not_empty key?-guards + this nil-guard together reproduce the oracle).
    def member?(raw, value)
      return false if raw.nil?
      Array(raw).map { |e| e.to_s }.include?(value.to_s) || raw.to_s == value.to_s
    end

    def match?(properties)
      properties ||= {}
      raw = properties[@field]

      case @operator
      when 'equal'
        member?(raw, @value)
      when 'not_equal'
        # SQL where.not(`-> 'f' ? 'v'`): `?` on a MISSING key is NULL and WHERE NOT NULL is falsy, so a
        # missing-key row is EXCLUDED. Require the key present AND the membership false. (Oracle-confirmed.)
        properties.key?(@field) && !member?(raw, @value)
      when 'contains'
        txt = text_form(raw)
        !txt.nil? && txt.downcase.include?(@value.to_s.downcase)
      when 'not_contains'
        # SQL `NOT ILIKE` is NULL-propagating: a missing/NULL value yields NULL (row EXCLUDED), not true.
        txt = text_form(raw)
        !txt.nil? && !txt.downcase.include?(@value.to_s.downcase)
      when 'is_empty'
        member?(raw, '')
      when 'is_not_empty'
        # Same missing-key EXCLUSION as not_equal: `NOT (-> 'f' ? '')` drops the missing-key row.
        properties.key?(@field) && !member?(raw, '')
      when 'less', 'less_or_equal', 'greater', 'greater_or_equal'
        ordered_compare(raw, @operator)
      when 'between'
        between_compare(raw)
      else
        false
      end
    end

    # Reproduce `(properties ->> 'f')[::int] <op> 'v' AND properties ->> 'f' != ''`.
    def ordered_compare(raw, operator)
      lhs = text_form(raw)
      return false if lhs.nil? || lhs == '' # the `!= ''` guard (and NULL-excludes)

      if integer?
        l = numeric(lhs); r = numeric(@value)
        return false if l.nil? || r.nil? # ::int would have raised / excluded a non-numeric
      else
        l = lhs; r = @value.to_s
      end

      case operator
      when 'less'             then l <  r
      when 'less_or_equal'    then l <= r
      when 'greater'          then l >  r
      when 'greater_or_equal' then l >= r
      end
    end

    # Reproduce `(properties ->> 'f')[::int] BETWEEN 'first' AND 'last' AND properties ->> 'f' != ''`.
    def between_compare(raw)
      lhs = text_form(raw)
      return false if lhs.nil? || lhs == ''
      first = Array(@value).first
      last  = Array(@value).last

      if integer?
        l = numeric(lhs); f = numeric(first); t = numeric(last)
        return false if l.nil? || f.nil? || t.nil?
      else
        l = lhs; f = first.to_s; t = last.to_s
      end
      l >= f && l <= t
    end

    def numeric(v)
      Float(v)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
