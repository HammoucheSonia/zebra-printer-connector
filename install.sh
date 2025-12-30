#!/bin/sh
# install.sh - Version robuste avec échappement sed

set -e

echo "========================================"
echo "🚀 INSTALLATION AVOGREEN ZEBRA CONNECTOR"
echo "========================================"

# Vérifier root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ ERREUR : sudo sh install.sh"
    exit 1
fi

# Configuration
INSTALL_DIR="/opt/avogreen-printer"
SERVICE_NAME="avogreen-printer"

# 1. Python
echo "[1/6] Vérification de Python..."
command -v python3 >/dev/null 2>&1 || {
    echo "📦 Installation de Python3..."
    apt-get update && apt-get install -y python3 2>/dev/null || \
    yum install -y python3 2>/dev/null || \
    dnf install -y python3 2>/dev/null || \
    zypper install -y python3 2>/dev/null || {
        echo "❌ Impossible d'installer Python3"
        exit 1
    }
}

# 2. Répertoire
echo "[2/6] Création du répertoire..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 3. Configuration
echo "[3/6] Configuration de l'imprimante..."
echo ""

# Lire avec valeurs par défaut claires
printf "Adresse IP de l'imprimante Zebra [192.168.1.22]: "
read ZEBRA_IP
ZEBRA_IP=${ZEBRA_IP:-192.168.1.22}

printf "Port de l'imprimante [9100]: "
read ZEBRA_PORT
ZEBRA_PORT=${ZEBRA_PORT:-9100}

printf "Port du proxy [9090]: "
read PROXY_PORT
PROXY_PORT=${PROXY_PORT:-9090}

# 4. Créer le fichier Python DIRECTEMENT avec les bonnes valeurs
echo "[4/6] Création du connecteur..."
cat > printer_connector.py << EOF
#!/usr/bin/env python3
"""
Avogreen Printer Connector
"""
import socket
import json
import logging
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

# Configuration
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
            logger.info(f"📨 Commande reçue ({len(zpl_data)} octets)")
            
            # Envoyer à l'imprimante
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(10)
                sock.connect((ZEBRA_IP, ZEBRA_PORT))
                sock.sendall(zpl_data)
            
            logger.info(f"✅ Imprimé sur {ZEBRA_IP}:{ZEBRA_PORT}")
            self.send_response(200)
            response = {"status": "success", "printer": ZEBRA_IP}
            
        except socket.timeout:
            logger.error(f"⏱️ Timeout : imprimante {ZEBRA_IP} inaccessible")
            self.send_response(408)
            response = {"status": "error", "reason": "timeout"}
            
        except ConnectionRefusedError:
            logger.error(f"🚫 Connexion refusée : {ZEBRA_IP}:{ZEBRA_PORT}")
            self.send_response(503)
            response = {"status": "error", "reason": "connection_refused"}
            
        except Exception as e:
            logger.error(f"❌ Erreur: {e}")
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
        
        # Test connexion
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(3)
                s.connect((ZEBRA_IP, ZEBRA_PORT))
                printer_ok = True
        except:
            printer_ok = False
        
        status = {
            "service": "avogreen-printer-connector",
            "version": "2.0",
            "status": "running",
            "printer_connected": printer_ok,
            "printer_ip": ZEBRA_IP,
            "printer_port": ZEBRA_PORT,
            "proxy_port": PROXY_PORT,
            "timestamp": time.time()
        }
        self.wfile.write(json.dumps(status, indent=2).encode())
    
    def log_message(self, format, *args):
        logger.info(format % args)

def run_server():
    """Démarre le serveur"""
    server = HTTPServer(('0.0.0.0', PROXY_PORT), PrinterHandler)
    logger.info(f"🚀 Connecteur démarré sur le port {PROXY_PORT}")
    logger.info(f"📡 Imprimante cible: {ZEBRA_IP}:{ZEBRA_PORT}")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Arrêt du connecteur...")
        server.server_close()

if __name__ == '__main__':
    print(f"Avogreen Printer Connector v2.0")
    print(f"Imprimante: {ZEBRA_IP}:{ZEBRA_PORT}")
    print(f"Proxy: 0.0.0.0:{PROXY_PORT}")
    run_server()
EOF

chmod +x printer_connector.py

# 5. Service systemd
echo "[5/6] Configuration du service systemd..."
cat > /etc/systemd/system/"$SERVICE_NAME".service << EOF
[Unit]
Description=Avogreen Zebra Printer Connector
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/printer_connector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 6. Démarrer
echo "[6/6] Démarrage du service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# 7. Vérification
sleep 2
echo ""
echo "========================================"
echo "✅ INSTALLATION RÉUSSIE"
echo "========================================"

# IPs
IPV4=$(curl -s -4 icanhazip.com 2>/dev/null || echo "VOTRE-IP")
echo "📡 URL À FOURNIR :"
echo "   http://$IPV4:$PROXY_PORT"
echo ""
echo "🔍 TEST :"
echo "   curl http://localhost:$PROXY_PORT"
echo ""
echo "⚙️  CONFIG :"
echo "   Imprimante: $ZEBRA_IP:$ZEBRA_PORT"
echo "========================================"

if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
    echo "🎉 Service actif !"
    curl -s http://localhost:$PROXY_PORT | python3 -m json.tool 2>/dev/null || echo "Test API..."
else
    echo "❌ Service inactif"
fi