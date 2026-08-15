# frozen_string_literal: true

# Resolve active RESULT catalog CSV paths (dated or legacy undated).
# Archive files such as create_RESULTcatalogOUTPUT_level_2024_2026_olddupes.csv are never selected.

module ResultcatalogPathsLib
  module_function

  CATALOG_FILENAME_PREFIX = 'create_RESULTcatalogOUTPUT'

  def dated_catalog_filename?(family, path)
    File.basename(path).match?(
      /\A#{Regexp.escape(CATALOG_FILENAME_PREFIX)}_#{Regexp.escape(family)}_\d{4}_\d{4}\.csv\z/
    )
  end

  def olddupes_catalog_filename?(family, path)
    File.basename(path).match?(
      /\A#{Regexp.escape(CATALOG_FILENAME_PREFIX)}_#{Regexp.escape(family)}_\d{4}_\d{4}_olddupes\.csv\z/
    )
  end

  def catalog_candidate_paths(catalog_dir, family)
    Dir.glob(File.join(catalog_dir, "#{CATALOG_FILENAME_PREFIX}_#{family}_*.csv"))
       .reject { |path| olddupes_catalog_filename?(family, path) }
  end

  def resolve_catalog_path(catalog_dir, family)
    dated = catalog_candidate_paths(catalog_dir, family)
            .select { |path| dated_catalog_filename?(family, path) }
            .sort
    return dated.last if dated.any?

    legacy = File.join(catalog_dir, "#{CATALOG_FILENAME_PREFIX}_#{family}.csv")
    return legacy if File.exist?(legacy)

    raise "Missing #{family} catalog under #{catalog_dir}"
  end
end
