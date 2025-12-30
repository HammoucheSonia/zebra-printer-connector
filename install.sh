#!/bin/bash
# install.sh - Version FINALE et FONCTIONNELLE
set -e

echo "========================================"
echo "🚀 INSTALLATION AVOGREEN ZEBRA CONNECTOR"
echo "========================================"

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "❌ sudo bash install.sh"
    exit 1
fi

# Ask for config
echo ""
read -p "IP imprimante [192.168.1.22]: " ip
ip=${ip:-192.168.1.22}

read -p "Port imprimante [9100]: " port
port=${port:-9100}

read -p "Port proxy [9090]: " proxy
proxy=${proxy:-9090}

# Create directory
mkdir -p /opt/avogreen-printer
cd /opt/avogreen-printer

# Create Python file
cat > printer_connector.py << PYEOF
#!/usr/bin/env python3
import socket, json, logging
from http.server import HTTPServer, BaseHTTPRequestHandler

ZEBRA_IP = "$ip"
ZEBRA_PORT = $port
PROXY_PORT = $proxy

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            length = int(self.headers['Content-Length'])
            data = self.rfile.read(length)
            logger.info(f"Reçu {len(data)} octets")
            
            with socket.socket() as s:
                s.settimeout(5)
                s.connect((ZEBRA_IP, ZEBRA_PORT))
                s.sendall(data)
            
            self.send_response(200)
            response = {"status": "success"}
        except Exception as e:
            logger.error(f"Erreur: {e}")
            self.send_response(500)
            response = {"status": "error"}
        
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())
    
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        try:
            with socket.socket() as s:
                s.settimeout(2)
                s.connect((ZEBRA_IP, ZEBRA_PORT))
                connected = True
        except:
            connected = False
        
        self.wfile.write(json.dumps({
            "service": "avogreen-printer",
            "printer_ip": ZEBRA_IP,
            "connected": connected,
            "port": PROXY_PORT
        }).encode())
    
    def log_message(self, format, *args):
        logger.info(format % args)

print(f"Connecteur démarré sur {PROXY_PORT}")
HTTPServer(('0.0.0.0', PROXY_PORT), Handler).serve_forever()
PYEOF

chmod +x printer_connector.py

# Create service
cat > /etc/systemd/system/avogreen-printer.service << EOF
[Unit]
Description=Avogreen Printer Connector
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/avogreen-printer/printer_connector.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start
systemctl daemon-reload
systemctl enable avogreen-printer
systemctl start avogreen-printer

sleep 2

# Show info
echo ""
echo "✅ INSTALLATION RÉUSSIE"
echo "========================"
echo "URL: http://\$(curl -s icanhazip.com):$proxy"
echo "Test: curl http://localhost:$proxy"
echo "Imprimante: $ip:$port"
echo "========================"

if systemctl is-active --quiet avogreen-printer; then
    echo "Service actif ✓"
else
    echo "Service inactif ✗"
fi
