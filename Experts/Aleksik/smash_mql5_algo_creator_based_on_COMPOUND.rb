#!/usr/bin/env ruby
# frozen_string_literal: true

# Bulk-creates quant algos in aleksik.mq5 from compound.csv (analyze_subvariants export).
# Each row: copy magic_prefix base algo, add variables as quant rules, gate session via analysis_set.
#
# Usage:
#   ruby smash_mql5_algo_creator_based_on_COMPOUND.rb
#   ruby smash_mql5_algo_creator_based_on_COMPOUND.rb --dry-run
#   ruby smash_mql5_algo_creator_based_on_COMPOUND.rb path/to/other.csv

require 'csv'
require_relative 'smash_mql5_algo_creator_common'

include SmashMql5AlgoCreatorCommon

COMPOUND_CSV = File.expand_path('compound.csv', __dir__)

REQUIRED_COLUMNS = %w[
  analysis_set
  magic_prefix
  variables
].freeze

def compound_csv_path
  custom = ARGV.reject { |a| a.start_with?('--') }.first
  custom ? File.expand_path(custom) : COMPOUND_CSV
end

def dry_run?
  ARGV.include?('--dry-run')
end

def load_compound_rows(path)
  raise "Compound CSV not found: #{path}" unless File.file?(path)

  table = CSV.read(path, headers: true)
  missing = REQUIRED_COLUMNS - table.headers.map(&:to_s)
  raise "Compound CSV missing column(s): #{missing.join(', ')}" unless missing.empty?

  rows = []
  table.each.with_index(2) do |row, line_no|
    variables = row['variables'].to_s.strip
    next if variables.empty?

    rows << {
      line_no: line_no,
      analysis_set: row['analysis_set'].to_s.strip,
      magic_prefix: row['magic_prefix'].to_s.strip.to_i,
      variables: variables,
      grp_pf: row['grp_pf'].to_s.strip,
      grp_trades: row['grp_trades'].to_s.strip,
      variable_count: row['variable_count'].to_s.strip
    }
  end

  raise "Compound CSV has no data rows with variables: #{path}" if rows.empty?

  rows
end

def session_config_for_analysis_set(analysis_set)
  name = analysis_set.to_s.strip
  raise 'Row has empty analysis_set' if name.empty?

  if name.casecmp('full').zero?
    { enabled: false, rule: nil }
  else
    { enabled: true, rule: name }
  end
end

def extra_tokens_for_row(row)
  session_cfg = session_config_for_analysis_set(row[:analysis_set])
  extra_rule_tokens_from_quant(
    extra_rules_quant: row[:variables],
    session_rule_enabled: session_cfg[:enabled],
    session_rule: session_cfg[:rule]
  )
end

def validate_rows!(content, rows)
  validate_algo_slot_capacity!(content, rows.size)

  used_ids = existing_algo_ids(content)
  missing_sources = rows.map { |r| r[:magic_prefix] }.uniq.reject { |id| used_ids.include?(id) }
  unless missing_sources.empty?
    raise "magic_prefix source algo(s) not wired in #{MQ5_FILE}: #{missing_sources.sort.join(', ')}"
  end

  rows.each do |row|
    tokens = extra_tokens_for_row(row)
    validate_rule_tokens!(tokens)
  rescue StandardError => e
    raise "Compound CSV line #{row[:line_no]} (prefix #{row[:magic_prefix]}, #{row[:analysis_set]}): #{e.message}"
  end
end

def create_algo_from_row!(content, row)
  source_id = row[:magic_prefix]
  new_id = next_unused_algo_id(content)
  extra_tokens = extra_tokens_for_row(row)

  b1 = extract_inner(content, 1)
  b2 = extract_inner(content, 2)
  b4 = extract_inner(content, 4)

  content = replace_inner(content, 1, update_block1(b1, new_id))
  content = replace_inner(content, 2, update_block2_copy(b2, source_id, new_id))
  content = replace_inner(content, 4, append_rule_case_cloned_from(b4, source_id, new_id, extra_tokens))
  content = finalize_mq5!(content)

  [content, new_id, extra_tokens]
end

def print_capacity_report(content, row_count)
  used = existing_algo_ids(content)
  remaining = remaining_algo_slot_count(content)
  puts format(
    'Algo ID capacity: %d CSV row(s), %d free slot(s), %d wired (%d..%d), range %d..%d',
    row_count,
    remaining,
    used.size,
    used.first,
    used.last,
    MIN_ALGO_ID,
    MAX_ALGO_ID
  )
end

def run_compound_bulk!(csv_path:, dry_run: false)
  rows = load_compound_rows(csv_path)
  content = read_mq5

  print_capacity_report(content, rows.size)
  validate_rows!(content, rows)

  if dry_run
    puts
    puts "Dry run OK: #{rows.size} quant algo(s) would be created from #{csv_path}"
    rows.first(5).each do |row|
      tokens = extra_tokens_for_row(row)
      puts format(
        '  line %d | copy %d | %s | %d rule(s) | pf=%s trades=%s',
        row[:line_no],
        row[:magic_prefix],
        row[:analysis_set],
        tokens.size,
        row[:grp_pf],
        row[:grp_trades]
      )
    end
    puts "  ... (#{rows.size - 5} more)" if rows.size > 5
    return rows.size
  end

  created = []
  rows.each do |row|
    content, new_id, extra_tokens = create_algo_from_row!(content, row)
    created << {
      line_no: row[:line_no],
      new_id: new_id,
      source_id: row[:magic_prefix],
      analysis_set: row[:analysis_set],
      rule_count: extra_tokens.size,
      grp_pf: row[:grp_pf],
      grp_trades: row[:grp_trades]
    }
    puts format(
      'Created algo %d from %d | line %d | %s | pf=%s grp_trades=%s | %d quant rule(s)',
      new_id,
      row[:magic_prefix],
      row[:line_no],
      row[:analysis_set],
      row[:grp_pf],
      row[:grp_trades],
      extra_tokens.size
    )
  end

  write_mq5!(content)

  puts
  puts "Created #{created.size} quant algo(s) in #{MQ5_FILE}"
  puts "New IDs: #{created.map { |c| c[:new_id] }.join(', ')}"
  created.size
end

if __FILE__ == $PROGRAM_NAME
  run_compound_bulk!(csv_path: compound_csv_path, dry_run: dry_run?)
end
