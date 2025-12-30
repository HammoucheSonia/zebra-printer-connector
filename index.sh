
set -e

echo "========================================"
echo "🚀 INSTALLATION AVOGREEN ZEBRA CONNECTOR"
echo "========================================"

# Vérifier root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Exécutez avec : sudo bash install.sh"
    exit 1
fi

# Demander configuration
echo ""
echo "Configuration de l'imprimante :"
echo "--------------------------------"

read -p "IP de l'imprimante Zebra [192.168.1.22]: " ZEBRA_IP
ZEBRA_IP=${ZEBRA_IP:-192.168.1.22}

read -p "Port de l'imprimante [9100]: " ZEBRA_PORT
ZEBRA_PORT=${ZEBRA_PORT:-9100}

read -p "Port du proxy [9090]: " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-9090}

# Créer répertoire
mkdir -p /opt/avogreen-printer
cd /opt/avogreen-printer

# Créer le fichier Python AVEC les bonnes variables
cat > printer_connector.py << EOF
#!/usr/bin/env python3
"""
Avogreen Printer Connector
"""
import socket
import json
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler

# Configuration - LES VARIABLES SONT ICI
ZEBRA_IP = "$ZEBRA_IP"
ZEBRA_PORT = $ZEBRA_PORT
PROXY_PORT = $PROXY_PORT

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/avogreen-printer.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class PrinterHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        """Reçoit les commandes ZPL depuis Avogreen"""
        try:
            content_length = int(self.headers['Content-Length'])
            zpl_data = self.rfile.read(content_length)
            logger.info(f"Reçu {len(zpl_data)} octets")
            
            # Envoyer à l'imprimante
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(10)
                sock.connect((ZEBRA_IP, ZEBRA_PORT))
                sock.sendall(zpl_data)
            
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
        """Health check"""
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        # Tester la connexion
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(3)
                s.connect((ZEBRA_IP, ZEBRA_PORT))
                connected = True
        except:
            connected = False
        
        status = {
            "service": "avogreen-printer",
            "status": "running",
            "printer_connected": connected,
            "printer_ip": ZEBRA_IP,
            "printer_port": ZEBRA_PORT,
            "proxy_port": PROXY_PORT
        }
        self.wfile.write(json.dumps(status, indent=2).encode())
    
    def log_message(self, format, *args):
        logger.info(format % args)

print(f"Connecteur démarré sur le port {PROXY_PORT}")
HTTPServer(('0.0.0.0', PROXY_PORT), PrinterHandler).serve_forever()
EOF

# Rendre exécutable
chmod +x printer_connector.py

# Créer service systemd
cat > /etc/systemd/system/avogreen-printer.service << EOF
[Unit]
Description=Avogreen Zebra Printer Connector
After=network.target

[Service]
Type=simple
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
sleep 2

# Obtenir IP publique
PUBLIC_IP=$(curl -s icanhazip.com || echo "VOTRE-IP")

# Afficher résultats
echo ""
echo "✅ INSTALLATION RÉUSSIE"
echo "========================"
echo "📡 URL À FOURNIR :"
echo "   http://${PUBLIC_IP}:${PROXY_PORT}"
echo ""
echo "🔍 TEST :"
echo "   curl http://localhost:${PROXY_PORT}"
echo ""
echo "⚙️  CONFIGURATION :"
echo "   Imprimante: ${ZEBRA_IP}:${ZEBRA_PORT}"
echo "========================"

# Vérifier
if systemctl is-active --quiet avogreen-printer; then
    echo "🎉 Service actif !"
    echo "Test API :"
    curl -s http://localhost:${PROXY_PORT} | head -c 100
    echo ""
else
    echo "❌ Service inactif"
fi