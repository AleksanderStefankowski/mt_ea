# frozen_string_literal: true

# Keep in sync with aleksik.mq5 RebuildFalgoCalendarOverrideDateLists() nonTrade[].
# These dates are banned for algo trading (FalgoIsNonTradeCalendarDate).

module AleksikNonTradeCalendar
  NON_TRADE_DATES = [
    # 2024 — market holidays
    '2024.01.01', '2024.01.15', '2024.02.19', '2024.03.29', '2024.05.27', '2024.06.19',
    '2024.07.04', '2024.09.02', '2024.11.28', '2024.12.25',
    # 2024 — early close / special
    '2024.07.03', '2024.11.29', '2024.12.24',
    # 2024 — OpEx weeks (Mon–Fri)
    '2024.03.11', '2024.03.12', '2024.03.13', '2024.03.14', '2024.03.15',
    '2024.06.17', '2024.06.18', '2024.06.20', '2024.06.21',
    '2024.09.16', '2024.09.17', '2024.09.18', '2024.09.19', '2024.09.20',
    '2024.12.16', '2024.12.17', '2024.12.18', '2024.12.19', '2024.12.20',
    # 2025 — market holidays
    '2025.01.01', '2025.01.20', '2025.02.17', '2025.04.18', '2025.05.26', '2025.06.19',
    '2025.07.04', '2025.09.01', '2025.11.27', '2025.12.25',
    # 2025 — early close / special
    '2025.07.03', '2025.11.28', '2025.12.24',
    # 2025 — OpEx weeks (Mon–Fri)
    '2025.03.17', '2025.03.18', '2025.03.19', '2025.03.20', '2025.03.21',
    '2025.06.16', '2025.06.17', '2025.06.18', '2025.06.20',
    '2025.09.15', '2025.09.16', '2025.09.17', '2025.09.18', '2025.09.19',
    '2025.12.15', '2025.12.16', '2025.12.17', '2025.12.18', '2025.12.19',
    # 2026 — market holidays
    '2026.01.01', '2026.01.19', '2026.02.16', '2026.04.03', '2026.05.25', '2026.06.19',
    '2026.07.03', '2026.09.07', '2026.11.26', '2026.12.25',
    # 2026 — OpEx weeks (Mon–Fri)
    '2026.03.16', '2026.03.17', '2026.03.18', '2026.03.19', '2026.03.20',
    '2026.06.15', '2026.06.16', '2026.06.17', '2026.06.18',
    '2026.09.14', '2026.09.15', '2026.09.16', '2026.09.17', '2026.09.18',
    '2026.12.14', '2026.12.15', '2026.12.16', '2026.12.17', '2026.12.18'
  ].freeze

  NON_TRADE_DATE_SET = NON_TRADE_DATES.to_set.freeze

  def self.normalize_date_str(date_str)
    date_str.to_s.strip.tr('-', '.')
  end

  def self.date_to_calendar_str(date)
    format('%04d.%02d.%02d', date.year, date.month, date.day)
  end

  def self.non_trade_date?(date_or_str)
    key =
      case date_or_str
      when Date
        date_to_calendar_str(date_or_str)
      else
        normalize_date_str(date_or_str)
      end
    NON_TRADE_DATE_SET.include?(key)
  end
end
