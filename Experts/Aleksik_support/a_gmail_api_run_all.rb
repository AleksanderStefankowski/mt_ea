# run_first_then_second.rb

def run_step!(cmd)
  puts ">> #{cmd}"
  success = system(cmd)
  abort("Command failed (exit #{$?.exitstatus}): #{cmd}") unless success
end

run_step!("python a_gmail_api.py")

sleep 2

run_step!("python a_gmail_api2step_parse_append_to_ALLRAW.py")

sleep 2

run_step!("python a_gmail_api3step_processDuplicates__saveAs_zeFinal2.py")
