import psutil
import time
import csv
import os
import requests
from datetime import datetime

INTERVAL = 600  # 10 minutes = 600 seconds

script_dir = os.path.dirname(os.path.abspath(__file__))
filename = os.path.join(script_dir, "computer_log.csv")  # keep .csv extension

def parse_temp(value):
    try:
        s = str(value).replace(",", ".")
        s = s.split()[0]  # remove units like "°C"
        return float(s)
    except:
        return None

def get_temps():
    cpu_temp = None
    gpu_temp = None
    try:
        data = requests.get("http://127.0.0.1:8085/data.json").json()

        def walk(node):
            nonlocal cpu_temp, gpu_temp
            if node.get("Type") == "Temperature" and "Value" in node:
                name = node["Text"].lower()
                value = parse_temp(node["Value"])
                if value is not None:
                    if "cpu package" in name:
                        cpu_temp = value
                    elif "gpu core" in name:
                        gpu_temp = value
            for child in node.get("Children", []):
                walk(child)

        walk(data)
    except Exception as e:
        print("Error reading temps:", e)

    return cpu_temp, gpu_temp

print("Logger started. Press Ctrl+C to stop.")

# CSV header
with open(filename, "a", newline="") as f:
    writer = csv.writer(f, delimiter='\t')  # <--- tab-separated
    if f.tell() == 0:
        writer.writerow([
            "timestamp",
            "cpu_temp_c",
            "gpu_temp_c",
            "cpu_free_percent",
            "ram_free_percent"
        ])

while True:
    timestamp = datetime.now().isoformat()
    cpu_used = psutil.cpu_percent(interval=1)
    cpu_free = 100 - cpu_used
    ram = psutil.virtual_memory()
    ram_free = 100 - ram.percent
    cpu_temp, gpu_temp = get_temps()
    row = [
        timestamp,
        cpu_temp,
        gpu_temp,
        round(cpu_free, 2),
        round(ram_free, 2)
    ]
    with open(filename, "a", newline="") as f:
        csv.writer(f, delimiter='\t').writerow(row)
    print(row)
    time.sleep(INTERVAL)