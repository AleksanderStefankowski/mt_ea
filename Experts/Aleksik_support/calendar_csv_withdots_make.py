import csv
from datetime import date

# Output: date column in YYYY.MM.DD (dots) to match MT5 TimeToString(..., TIME_DATE)
out_path = r"c:\Users\Aleks\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856\MQL5\Experts\Aleksik_support\calendar_2026_dots.csv"
start = date(2018, 1, 1)
end = date(2027, 12, 31)

def is_third_friday(d):
    # Friday = 4 (Monday=0), 3rd week of month = (day-1)//7 == 2
    return d.weekday() == 4 and (d.day - 1) // 7 == 2

with open(out_path, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["date", "dayofmonth", "dayofweek", "opex", "qopex"])
    d = start
    while d <= end:
        opex = is_third_friday(d)
        qopex = opex and d.month in (3, 6, 9, 12)
        w.writerow([
            d.strftime("%Y.%m.%d"),  # YYYY.MM.DD (dots) for MT5
            d.day,
            d.strftime("%A"),
            opex,
            qopex,
        ])
        d = date.fromordinal(d.toordinal() + 1)
