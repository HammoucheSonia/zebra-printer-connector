#!/bin/bash
# install.sh - Connecteur Avogreen pour imprimantes Zebra
# Version finale - Décembre 2025

set -e

echo "========================================"
echo "🚀 INSTALLATION AVOGREEN ZEBRA CONNECTOR"
echo "========================================"

# Vérifier root
if [[ $EUID -ne 0 ]]; then
    echo "❌ ERREUR : Exécutez avec : sudo bash install.sh"
    exit 1
fi

# Demander configuration
echo ""
echo "Configuration de l'imprimante :"
echo "--------------------------------"

read -p "Adresse IP de l'imprimante Zebra [192.168.1.22]: " ZEBRA_IP
ZEBRA_IP=${ZEBRA_IP:-192.168.1.22}

read -p "Port de l'imprimante [9100]: " ZEBRA_PORT
ZEBRA_PORT=${ZEBRA_PORT:-9100}

read -p "Port du proxy [9090]: " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-9090}

# Créer répertoire
INSTALL_DIR="/opt/avogreen-printer"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Créer le fichier Python
echo "Création du connecteur..."
cat > printer_connector.py << EOF
#!/usr/bin/env python3
"""
Avogreen Printer Connector
"""
import socket
import json
import logging
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
        
        # Tester la connexion à l'imprimante
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(3)
                s.connect((ZEBRA_IP, ZEBRA_PORT))
                printer_ok = True
        except:
            printer_ok = False
        
        status = {
            "service": "avogreen-printer-connector",
            "status": "running",
            "printer_connected": printer_ok,
            "printer_ip": ZEBRA_IP,
            "printer_port": ZEBRA_PORT,
            "proxy_port": PROXY_PORT
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
    print(f"Avogreen Printer Connector")
    print(f"Imprimante: {ZEBRA_IP}:{ZEBRA_PORT}")
    print(f"Proxy: 0.0.0.0:{PROXY_PORT}")
    run_server()
EOF

# Rendre exécutable
chmod +x printer_connector.py

# Créer le service systemd
echo "Configuration du service..."
cat > /etc/systemd/system/avogreen-printer.service << EOF
[Unit]
Description=Avogreen Zebra Printer Connector
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/printer_connector.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Démarrer le service
systemctl daemon-reload
systemctl enable avogreen-printer
systemctl start avogreen-printer

# Attendre un peu
sleep 3

# Obtenir l'IP publique
echo ""
echo "Récupération de l'IP publique..."
PUBLIC_IP=$(curl -s -4 icanhazip.com || curl -s ifconfig.me || hostname -I | awk '{print $1}' || echo "VOTRE-IP")

# Afficher les informations
echo ""
echo "========================================"
echo "✅ INSTALLATION RÉUSSIE"
echo "========================================"
echo "📡 URL À FOURNIR À AVOGREEN :"
echo "   http://${PUBLIC_IP}:${PROXY_PORT}"
echo ""
echo "🔍 COMMANDES DE VÉRIFICATION :"
echo "   sudo systemctl status avogreen-printer"
echo "   curl http://localhost:${PROXY_PORT}"
echo "   sudo journalctl -u avogreen-printer -f"
echo ""
echo "⚙️  CONFIGURATION :"
echo "   Imprimante: ${ZEBRA_IP}:${ZEBRA_PORT}"
echo "   Modifier: sudo nano ${INSTALL_DIR}/printer_connector.py"
echo "========================================"

# Tester
if systemctl is-active --quiet avogreen-printer; then
    echo "🎉 Service actif et fonctionnel !"
    echo ""
    echo "Test de l'API :"
    curl -s http://localhost:${PROXY_PORT} | head -c 200
    echo ""
else
    echo "⚠️  Service inactif - vérifiez les logs :"
    journalctl -u avogreen-printer -n 10 --no-pager
fi