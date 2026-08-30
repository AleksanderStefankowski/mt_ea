# frozen_string_literal: true

module AlertDoneCommon
  ALERT_MP3_PATH = File.expand_path('alert.mp3', __dir__)

  module_function

  def play_alert_done!
    return if ENV['SKIP_ALERT_DONE'] == '1'
    return unless File.file?(ALERT_MP3_PATH)

    path = ALERT_MP3_PATH.gsub("'", "''")
    system(
      'powershell',
      '-NoProfile',
      '-Command',
      "Add-Type -AssemblyName PresentationCore; $player = New-Object System.Windows.Media.MediaPlayer; " \
      "$player.Open((Get-Item '#{path}').FullName); $player.Play(); Start-Sleep -Seconds 2"
    )
  rescue StandardError => e
    warn "WARNING: alert sound failed: #{e.message}"
  end
end

def play_alert_done!
  AlertDoneCommon.play_alert_done!
end
