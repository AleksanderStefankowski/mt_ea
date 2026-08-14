# frozen_string_literal: true

require "csv"

module CatalogCreatorCommon
  module_function

  WITHIN_CATALOG_ID_COLUMN = "within-catalog-id"
  RESULTCATALOG_DIR = File.expand_path("../Aleksik_traderesults2_breakdown", __dir__)

  def resolve_catalog_path(family)
    dated = Dir.glob(File.join(RESULTCATALOG_DIR, "create_RESULTcatalogOUTPUT_#{family}_*.csv")).sort
    return dated.last if dated.any?

    legacy = File.join(RESULTCATALOG_DIR, "create_RESULTcatalogOUTPUT_#{family}.csv")
    return legacy if File.exist?(legacy)

    raise "Missing #{family} catalog under #{RESULTCATALOG_DIR}"
  end

  def parse_catalog_ids(text, prefix)
    letter = prefix.to_s.upcase
    text.each_line.filter_map do |line|
      stripped = line.strip
      next if stripped.empty?
      next if stripped.start_with?("#")

      unless stripped.match?(/\A#{letter}\d+\z/i)
        raise "ERROR: invalid catalog id line: #{line.inspect} (expected #{letter} followed by digits, e.g. #{letter}7)"
      end

      "#{letter}#{stripped[/\d+/].to_i}"
    end.uniq
  end

  def normalize_catalog_row(row)
    row.to_h.transform_keys(&:to_s).transform_values { |value| value.to_s.strip }
  end

  def catalog_rows_by_id(path, prefix)
    raise "Missing catalog: #{path}" unless File.exist?(path)

    table = CSV.read(path, headers: true)
    unless table.headers.include?(WITHIN_CATALOG_ID_COLUMN)
      raise "#{File.basename(path)} missing column: #{WITHIN_CATALOG_ID_COLUMN}"
    end

    letter = prefix.to_s.upcase
    rows_by_id = {}
    table.each do |csv_row|
      row = normalize_catalog_row(csv_row)
      catalog_id = row[WITHIN_CATALOG_ID_COLUMN]
      next if catalog_id.empty?

      catalog_id = "#{letter}#{catalog_id[/\d+/].to_i}"
      rows_by_id[catalog_id] = row
    end
    rows_by_id
  end

  def select_catalog_rows(catalog_ids, rows_by_id, limit)
    selected = []
    missing = []

    catalog_ids.first(limit).each do |catalog_id|
      row = rows_by_id[catalog_id]
      if row.nil?
        missing << catalog_id
        next
      end

      selected << row.merge(WITHIN_CATALOG_ID_COLUMN => catalog_id)
    end

    { rows: selected, missing: missing }
  end

  def csv_bool?(value)
    %w[true 1 yes].include?(value.to_s.strip.downcase)
  end

  def next_algo_ids(existing_ids, count, id_min, id_max)
    raise "Need at least one new algo id" if count <= 0

    ids = existing_ids.dup
    out = []
    candidate = ids.empty? ? id_min : ids.max + 1
    while out.size < count
      raise "Ran out of algo ids below #{id_max}" if candidate > id_max

      unless ids.include?(candidate)
        out << candidate
        ids << candidate
      end
      candidate += 1
    end
    out
  end
end
