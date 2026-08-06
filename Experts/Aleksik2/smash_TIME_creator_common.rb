# frozen_string_literal: true

require_relative "../Aleksik/smash_mql5_algo_reader_lib"

MQ5_FILE = File.expand_path("aleksik2.mq5", __dir__)

MARKERS = {
  1 => %w[//timealgocreator1start //timealgocreator1end],
  2 => %w[//timealgocreator2start //timealgocreator2end]
}.freeze

TIME_ALGO_ID_MIN = 10_000_001
TIME_ALGO_ID_MAX = 99_999_999

COMBO_FIELDS = %i[
  entry_hour
  entry_minute
  rule_switch_map
  secret_tp_profit_percent_min
  secret_tp_greenguard_pricediff_at_least
  max_trades_per_day
  max_open_positions
  stop_trading_TODAY_if_thisAlgo_todayTotal_trades_count
].freeze

ASSIGN_RE = /
  g_timeAlgos\[TimeAlgoSlotIndexByAlgoId\(TIME_ALGO_(\d+)\)\]\.(\w+)\s*=\s*([^;]+);
/x

module TimeCombinationsCommon
  module_function

  def marker_line_re(marker)
    /^\s*#{Regexp.escape(marker)}\s*$/
  end

  def extract_inner(content, block_num)
    start_marker, end_marker = MARKERS.fetch(block_num)
    lines = content.lines
    start_idx = lines.index { |l| l.match?(marker_line_re(start_marker)) }
    end_idx = lines.index { |l| l.match?(marker_line_re(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find block #{block_num} (#{start_marker} .. #{end_marker})"
    end

    lines[(start_idx + 1)...end_idx].join.rstrip
  end

  def replace_inner(content, block_num, new_inner)
    start_marker, end_marker = MARKERS.fetch(block_num)
    lines = content.lines
    start_idx = lines.index { |l| l.match?(marker_line_re(start_marker)) }
    end_idx = lines.index { |l| l.match?(marker_line_re(end_marker)) }
    unless start_idx && end_idx && end_idx > start_idx
      raise "Could not find block #{block_num} (#{start_marker} .. #{end_marker})"
    end

    before = lines[0..start_idx].join
    after = lines[end_idx..].join
    "#{before}#{new_inner.rstrip}\n#{after}"
  end

  def time_registry_max(content)
    m = content.match(/#define\s+TIME_ALGO_REGISTRY_MAX\s+(\d+)/)
    raise "TIME_ALGO_REGISTRY_MAX not found in #{MQ5_FILE}" unless m

    m[1].to_i
  end

  def time_registry_max_headroom(content)
    m = content.match(/#define\s+TIME_ALGO_REGISTRY_MAX_HEADROOM\s+(\d+)/)
    raise "TIME_ALGO_REGISTRY_MAX_HEADROOM not found in #{MQ5_FILE}" unless m

    m[1].to_i
  end

  def compute_registry_max_for_wired_count(wired_count)
    wired_count
  end

  def set_time_registry_max(content, new_max)
    unless content.sub!(
      /#define\s+TIME_ALGO_REGISTRY_MAX\s+\d+/,
      format("#define TIME_ALGO_REGISTRY_MAX                   %d", new_max)
    )
      raise "Failed to update TIME_ALGO_REGISTRY_MAX in #{MQ5_FILE}"
    end

    content
  end

  def registry_algo_ids(content)
    block = extract_inner(content, 1)
    block.scan(/TIME_ALGO_(\d+)/).flatten.map(&:to_i).uniq.sort
  end

  def time_const(algo_id)
    format("TIME_ALGO_%08d", algo_id)
  end

  def rebuild_registry_inner(all_ids)
    lines = []
    all_ids.each do |algo_id|
      const = time_const(algo_id)
      lines << "#define #{const}#{' ' * (28 - const.length)}#{algo_id}"
    end
    lines << ""
    lines << "int g_timeAlgoRegistryIds[] ="
    lines << "{"
    all_ids.each { |algo_id| lines << "   #{time_const(algo_id)}," }
    lines[-1] = lines[-1].sub(/,\z/, "") unless all_ids.empty?
    lines << "};"
    lines.join("\n")
  end

  def parse_id_list(text)
    text.each_line.filter_map do |line|
      stripped = line.strip
      next if stripped.empty?
      next if stripped.start_with?("#")

      raise "Invalid algo id line: #{line.inspect}" unless stripped.match?(/\A\d+\z/)

      stripped.to_i
    end.uniq.sort
  end

  def strip_mq5_value(raw)
    raw.strip.sub(%r{//.*}, "").strip
  end

  def params_by_algo_from_content(content)
    inner = extract_inner(content, 2)
    params = Hash.new { |hash, key| hash[key] = {} }
    inner.scan(ASSIGN_RE) do |id, field, value|
      params[id.to_i][field] = strip_mq5_value(value)
    end
    params
  end

  def normalize_combo_value(value)
    text = value.to_s.strip
    return "" if text.empty?

    downcased = text.downcase
    return "true" if %w[true 1 yes].include?(downcased)
    return "false" if %w[false 0 no].include?(downcased)

    return format("%.10g", Float(text)) if text.match?(/\A-?\d+(?:\.\d+)?\z/)

    text
  end

  def combo_signature(combo)
    COMBO_FIELDS.map { |field| normalize_combo_value(combo[field]) }.join("\x1f")
  end

  def combo_from_params(params)
    COMBO_FIELDS.to_h { |field| [field, normalize_combo_value(params[field.to_s])] }
  end

  def existing_combo_signatures(content)
    params_by_algo = params_by_algo_from_content(content)
    registry_algo_ids(content).map do |algo_id|
      combo_signature(combo_from_params(params_by_algo[algo_id] || {}))
    end.to_set
  end

  def format_mq5_double(value, decimals = 2)
    format("%.#{decimals}f", value.to_f)
  end

  def entry_time_label(hour, minute)
    format("%d:%02d", hour.to_i, minute.to_i)
  end
end
