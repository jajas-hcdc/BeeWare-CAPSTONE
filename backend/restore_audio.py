import sqlite3
import os
import shutil
import wave

db_path = 'backend/beeware.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Remove 0-second test rows
c.execute("DELETE FROM telemetry_records WHERE audio_file_path LIKE '%20260921_1642%' OR id IN (40, 41)")
conn.commit()
count = c.execute("SELECT COUNT(id) FROM telemetry_records").fetchone()[0]
print(f"Deleted test rows. Remaining records: {count}")
conn.close()

# Remove test wav files
for f in ['backend/recordings/BW-001-ALPHA_20260921_164216.wav', 'backend/recordings/BW-001-ALPHA_20260921_164220.wav']:
    if os.path.exists(f):
        os.remove(f)
        print(f"Removed {f}")

# Restore latest_hive_audio.wav from valid 3.0s recording
valid_wav = 'backend/recordings/BW-001-ALPHA_20260913_201350.wav'
if os.path.exists(valid_wav):
    shutil.copyfile(valid_wav, 'backend/latest_hive_audio.wav')
    w = wave.open('backend/latest_hive_audio.wav')
    duration = w.getnframes() / w.getframerate()
    size = os.path.getsize('backend/latest_hive_audio.wav')
    print(f"Restored latest_hive_audio.wav: Duration = {duration:.2f}s, size = {size} bytes")

