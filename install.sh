#!/bin/bash
# install.sh - Version SIMPLE et GARANTIE

set -e

echo "========================================"
echo "🚀 INSTALLATION AVOGREEN ZEBRA CONNECTOR"
echo "========================================"

# Vérifier root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Exécutez avec: sudo bash install.sh"
    exit 1
fi

# Demander config
echo ""
echo "Configuration :"
echo "---------------"

read -p "IP imprimante Zebra [192.168.1.22]: " ip
ip=${ip:-192.168.1.22}

read -p "Port imprimante [9100]: " port
port=${port:-9100}

read -p "Port proxy [9090]: " proxy
proxy=${proxy:-9090}

# Créer répertoire
mkdir -p /opt/avogreen-printer
cd /opt/avogreen-printer

# Écrire le fichier Python CORRECTEMENT
cat > printer_connector.py << PYEOF
#!/usr/bin/env python3
import socket, json, logging, time
from http.server import HTTPServer, BaseHTTPRequestHandler

ZEBRA_IP = "$ip"
ZEBRA_PORT = $port
PROXY_PORT = $proxy

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class PrinterHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            length = int(self.headers['Content-Length'])
            data = self.rfile.read(length)
            logger.info(f"Reçu {len(data)} octets")
            
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(10)
                sock.connect((ZEBRA_IP, ZEBRA_PORT))
                sock.sendall(data)
            
            logger.info(f"Envoyé à {ZEBRA_IP}:{ZEBRA_PORT}")
            self.send_response(200)
            response = {"status": "success"}
        except Exception as e:
            logger.error(f"Erreur: {e}")
            self.send_response(500)
            response = {"status": "error", "reason": str(e)}
        
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())
    
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(3)
                s.connect((ZEBRA_IP, ZEBRA_PORT))
                connected = True
        except:
            connected = False
        
        status = {
            "service": "avogreen-printer-connector",
            "status": "running",
            "printer_connected": connected,
            "printer_ip": ZEBRA_IP,
            "printer_port": ZEBRA_PORT,
            "proxy_port": PROXY_PORT
        }
        self.wfile.write(json.dumps(status, indent=2).encode())

if __name__ == '__main__':
    print(f"Avogreen Printer Connector")
    print(f"Imprimante: {ZEBRA_IP}:{ZEBRA_PORT}")
    print(f"Proxy: 0.0.0.0:{PROXY_PORT}")
    HTTPServer(('0.0.0.0', PROXY_PORT), PrinterHandler).serve_forever()
PYEOF

chmod +x printer_connector.py

# Service systemd
cat > /etc/systemd/system/avogreen-printer.service << EOF
[Unit]
Description=Avogreen Zebra Printer Connector
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/avogreen-printer
ExecStart=/usr/bin/python3 /opt/avogreen-printer/printer_connector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Démarrer
systemctl daemon-reload
systemctl enable avogreen-printer
systemctl start avogreen-printer

# Attendre
sleep 3

# Afficher résultats
public_ip=$(curl -s icanhazip.com || echo "VOTRE-IP")

echo ""
echo "========================================"
echo "✅ INSTALLATION RÉUSSIE"
echo "========================================"
echo "📡 URL À FOURNIR À AVOGREEN :"
echo "   http://${public_ip}:${proxy}"
echo ""
echo "🔍 TEST :"
echo "   curl http://localhost:${proxy}"
echo ""
echo "⚙️  CONFIGURATION :"
echo "   Imprimante: ${ip}:${port}"
echo "========================================"

# Tester
if systemctl is-active --quiet avogreen-printer; then
    echo "🎉 Service actif et fonctionnel !"
    echo "Test API..."
    curl -s http://localhost:${proxy} | head -c 200
    echo ""
else
    echo "⚠️  Service inactif"
    journalctl -u avogreen-printer -n 10 --no-pager
fi