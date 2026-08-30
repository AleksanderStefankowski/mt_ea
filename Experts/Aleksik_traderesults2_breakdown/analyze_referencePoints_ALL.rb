#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'alert_done_common'

# Run per-family reference-point scripts:
#   analyze_referencePoints_breakdown.rb
#   analyze_referencePoints_time.rb
#   analyze_referencePoints_level.rb
#
# Freshness: only this script writes/reads analyze_referencePoints_ALL_output_timestamp.txt.
# Re-run within 8 minutes skips family scripts. Family scripts run directly always refresh.

require 'rbconfig'
require 'open3'
require_relative 'analyze_algos_performance_common'

include AnalyzeAlgosPerformanceCommon

self.traderate_account_for_banned_days = false

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
OUTPUT_TIMESTAMP_PATH = File.join(SCRIPT_DIR, 'analyze_referencePoints_ALL_output_timestamp.txt')

FAMILY_SCRIPTS = [
  File.join(SCRIPT_DIR, 'analyze_referencePoints_breakdown.rb'),
  File.join(SCRIPT_DIR, 'analyze_referencePoints_time.rb'),
  File.join(SCRIPT_DIR, 'analyze_referencePoints_level.rb')
].freeze

SUCCESS_MARKERS = %w[DONE].freeze

def run_family_script!(path)
  unless File.file?(path)
    warn "ERROR: family script not found: #{path}"
    exit 1
  end

  warn
  warn "Running #{File.basename(path)}..."
  output, status = Open3.capture2e({ 'SKIP_ALERT_DONE' => '1' }, RbConfig.ruby, path)
  warn output unless output.empty?

  success = status.success? && SUCCESS_MARKERS.any? { |marker| output.include?(marker) }
  unless success
    warn "ERROR: #{File.basename(path)} did not finish successfully " \
         "(expected one of: #{SUCCESS_MARKERS.join(', ')})"
    exit 1
  end
end

if __FILE__ == $PROGRAM_NAME

if output_timestamp_recent?(OUTPUT_TIMESTAMP_PATH)
  warn
  warn "Skipping family scripts (#{output_timestamp_age_label(OUTPUT_TIMESTAMP_PATH)}; " \
       "stamp fresh within last #{OUTPUT_TIMESTAMP_MAX_AGE_SECONDS / 60} min)"
  warn
  warn 'RAN OK'
  play_alert_done!
  exit 0
end

FAMILY_SCRIPTS.each { |path| run_family_script!(path) }

write_output_timestamp_txt!(OUTPUT_TIMESTAMP_PATH)
warn
warn 'RAN OK'

end

play_alert_done! if __FILE__ == $PROGRAM_NAME
