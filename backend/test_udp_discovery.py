import socket
import json

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2.5)
msg = json.dumps({"event": "esp32_boot", "deviceId": "BW-013230", "mac": "24:6F:28:01:32:30"})
s.sendto(msg.encode("utf-8"), ("127.0.0.1", 8001))
print("Broadcasted simulated ESP32 boot beacon to 127.0.0.1:8001")

try:
    resp, addr = s.recvfrom(1024)
    print("SUCCESS: Received discovery reply from", addr, ":", resp.decode())
except Exception as e:
    print("Error receiving reply:", e)
s.close()
