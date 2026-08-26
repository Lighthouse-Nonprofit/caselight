# frozen_string_literal: true

# OCA feedback 2026-08-26 — Araceli's program list nests curricula under a top-level program.
# Our Casebook import flattened them to top level, which is what made the programs list cluttered.
# This task sets ProgramStream#parent_id from an explicit table.
#
# WHY A TABLE AND NOT A HEURISTIC: the enrollment overlap on the OCA box is extremely suggestive
# (Cultura Club 20/20 and Susto y Limpia 27/27 of their clients are ALSO in ¡Por Vida!; Celebración
# 37/38; El Joven Noble 160/165; Girasol 49/51; Mi Palabra 21/22; Ancestral Teachings 17/18; and
# Cara y Corazón 0/58, consistent with it being the parents/adults curriculum). That overlap is
# EVIDENCE FOR the table below — it is not the mechanism. Production parentage is set from a list a
# human confirmed, never from a similarity score.
#
# STATUS: ⚠ the map below is a DRAFT pending Araceli's written confirmation. Until then the task
# refuses to run without CONFIRM=1, and reports what it would do with DRY_RUN=1.
namespace :youth do
  # Curriculum name => top-level program name. nil means "stays top level".
  CURRICULUM_PARENTS = {
    'El Joven Noble'        => '¡Por Vida!',
    'Girasol'               => '¡Por Vida!',
    'Cultura Club'          => '¡Por Vida!',
    'Celebración'           => '¡Por Vida!',
    'Ancestral Teachings'   => '¡Por Vida!',
    'Mi Palabra'            => '¡Por Vida!',
    'Susto y Limpia'        => '¡Por Vida!',
    'Nurturing Our Futures' => '¡Por Vida!',
    # Cara y Corazón is the parents/adults curriculum — 0 of its 58 participants are in ¡Por Vida!,
    # so it is deliberately NOT nested there. Awaiting Araceli on whether it stands alone.
    'Cara y Corazón'        => nil
  }.freeze

  desc 'Nest youth curricula under their top-level program (DRY_RUN=1 to preview; CONFIRM=1 to apply)'
  task nest_curricula: :environment do
    youth_flavor!
    tenant  = ENV['TENANT'] || 'cases'
    dry_run = ENV['DRY_RUN'] == '1'

    unless dry_run || ENV['CONFIRM'] == '1'
      abort 'youth:nest_curricula — refusing to run. The parent map is a DRAFT pending OCA ' \
            'confirmation. Re-run with DRY_RUN=1 to preview, or CONFIRM=1 once confirmed.'
    end

    Apartment::Tenant.switch(tenant) do
      changed = skipped = missing = 0
      notes = []

      CURRICULUM_PARENTS.each do |child_name, parent_name|
        child = ProgramStream.find_by(name: child_name)
        if child.nil?
          missing += 1
          notes << "  - MISSING curriculum: #{child_name}"
          next
        end

        if parent_name.nil?
          if child.parent_id.present?
            notes << "  - #{child_name}: would DETACH from its parent (stays top level)"
            child.update!(parent_id: nil) unless dry_run
            changed += 1
          else
            skipped += 1
          end
          next
        end

        parent = ProgramStream.find_by(name: parent_name)
        if parent.nil?
          missing += 1
          notes << "  - MISSING parent program: #{parent_name} (for #{child_name})"
          next
        end

        if child.parent_id == parent.id
          skipped += 1
          next
        end

        notes << "  - #{child_name} -> #{parent_name}"
        child.update!(parent: parent) unless dry_run
        changed += 1
      end

      verb = dry_run ? 'WOULD change' : 'changed'
      puts "youth:nest_curricula [tenant=#{tenant}]: #{verb} #{changed}, unchanged #{skipped}, missing #{missing}."
      notes.each { |n| puts n }

      # Anything still top level that is not a known parent is worth a human look — it is either a
      # genuine top-level program or a curriculum nobody has placed yet.
      known_parents = CURRICULUM_PARENTS.values.compact.uniq
      unplaced = ProgramStream.top_level.where.not(name: known_parents + CURRICULUM_PARENTS.keys)
      if unplaced.any?
        puts '  UNPLACED (top level, not in the map — confirm with the org):'
        unplaced.order(:name).each { |ps| puts "    - #{ps.name}" }
      end
    end
  end
end
