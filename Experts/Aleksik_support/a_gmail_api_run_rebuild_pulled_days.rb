# Gmail API pull + rebuild only the (start,end) ranges in that pull.
# Git diff on levelsinfo_zeFinal.csv shows how far bad ingest reached.

def run_step!(cmd)
  puts ">> #{cmd}"
  success = system(cmd)
  abort("Command failed (exit #{$?.exitstatus}): #{cmd}") unless success
end

run_step!("python a_gmail_api.py")

sleep 2

run_step!("python a_gmail_api_rebuild_pulled_days.py")
