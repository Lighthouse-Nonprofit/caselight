# frozen_string_literal: true

module Reports
  # Bounded Ruby-side decrypt for property fields the sidecar can't answer —
  # numeric comparisons and date filters (GPA deltas, wages, incident dates).
  #
  # VOLUME CONTRACT: callers narrow the relation FIRST (by period, tracking,
  # program, ability scope); this class then decrypts only those candidates in
  # batches. Reports run at pilot scale (thousands of rows, not millions); if a
  # candidate set can grow unbounded, redesign the source, don't lift the cap.
  class DecryptedScan
    BATCH_SIZE = 500

    # Yields (record, properties_hash) for each candidate, IN THE CALLER'S ORDER.
    #
    # This deliberately does NOT use find_each: find_each discards any ORDER BY
    # and re-orders by primary key (it only logs a warning). Several callers
    # depend on order for correctness — "the FIRST Employed entry", "the LATEST
    # Aeries check-in", "the 100 newest report cards" — so an id-ordered scan
    # silently returns the wrong record whenever a row was entered out of date
    # order (backdated entry, Aeries backfill, Casebook import in row order).
    # Ordered offset batches keep the volume contract and the ordering.
    def self.each(relation)
      return enum_for(:each, relation) unless block_given?
      offset = 0
      loop do
        batch = relation.offset(offset).limit(BATCH_SIZE).to_a
        break if batch.empty?
        batch.each { |record| yield record, (record.properties || {}) }
        break if batch.size < BATCH_SIZE
        offset += BATCH_SIZE
      end
    end

    # Convenience: [{record:, props:}] — small candidate sets only.
    def self.rows(relation)
      each(relation).map { |record, props| { record: record, props: props } }
    end
  end
end
