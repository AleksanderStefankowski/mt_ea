# run_first_then_second.rb

system("python a_gmail_api.py")

sleep 2

system("python a_gmail_api2step_parse_append_to_ALLRAW.py")

sleep 2


system("python a_gmail_api3step_processDuplicates__saveAs_zeFinal2.py")
