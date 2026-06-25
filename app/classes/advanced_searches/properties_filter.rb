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
    def select(records)
      records.select { |record| match?(record.properties) }
    end

    private

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
