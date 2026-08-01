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

    # Yields (record, properties_hash) for each candidate.
    def self.each(relation)
      return enum_for(:each, relation) unless block_given?
      relation.find_each(batch_size: BATCH_SIZE) do |record|
        yield record, (record.properties || {})
      end
    end

    # Convenience: [{record:, props:}] — small candidate sets only.
    def self.rows(relation)
      each(relation).map { |record, props| { record: record, props: props } }
    end
  end
end
