#!/usr/bin/env ruby
# frozen_string_literal: true

# Deletes all quanted algos from aleksik.mq5 (LevelAbove / LevelBelow / LevelTag rules).
# Uses smash_mql5_algo_deleter for the actual removal.

require_relative 'smash_mql5_algo_deleter'
require_relative 'smash_mql5_algo_reader_lib'

def quanted_algo_ids_to_delete
  src = SmashMql5AlgoReader.load_mq5(SmashMql5AlgoCreatorCommon::MQ5_FILE)
  params_by_algo = SmashMql5AlgoReader.params_by_algo_from_src(src)
  algo_ids = SmashMql5AlgoReader.registry_algo_ids(src)
  rules_by_algo = SmashMql5AlgoReader.rules_by_algo_from_src(src, params_by_algo)

  algo_ids
    .select { |id| SmashMql5AlgoReader.contains_quant_rule?(rules_by_algo[id]) }
    .sort
    .reverse
end

if __FILE__ == $PROGRAM_NAME
  quanted_ids = quanted_algo_ids_to_delete

  if quanted_ids.empty?
    puts 'No quanted algos found — nothing to delete.'
    exit 0
  end

  puts "Quanted algos to delete (#{quanted_ids.size}): #{quanted_ids.join(', ')}"
  puts

  AlgoDeleter.run(delete_ids: quanted_ids)
end
