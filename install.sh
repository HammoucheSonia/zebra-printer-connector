

set -e

echo "========================================"
echo "🚀 INSTALLATION AVOGREEN ZEBRA CONNECTOR"
echo "========================================"

# Vérifier si on est root
if [ "$EUID" -ne 0 ]; then
    echo "❌ ERREUR : Ce script doit être exécuté avec sudo"
    echo "Usage : sudo ./install.sh"
    exit 1
fi

# Configuration
INSTALL_DIR="/opt/avogreen-printer"
SERVICE_NAME="avogreen-printer"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 1. Installer Python si nécessaire
echo "[1/6] Vérification de Python..."
if ! command -v python3 &> /dev/null; then
    echo "📦 Installation de Python3..."
    apt-get update && apt-get install -y python3 || \
    yum install -y python3 || \
    dnf install -y python3
fi

# 2. Créer le répertoire d'installation
echo "[2/6] Création du répertoire..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 3. Demander la configuration
echo "[3/6] Configuration de l'imprimante..."
echo ""

read -p "Adresse IP de l'imprimante Zebra [192.168.1.22]: " ZEBRA_IP
ZEBRA_IP=${ZEBRA_IP:-192.168.1.22}

read -p "Port de l'imprimante [9100]: " ZEBRA_PORT
ZEBRA_PORT=${ZEBRA_PORT:-9100}

read -p "Port du proxy [9090]: " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-9090}

# 4. Créer le script Python
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
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "success"}).encode())
            
        except Exception as e:
            logger.error(f"❌ Erreur: {e}")
            self.send_response(500)
            self.end_headers()
    
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
    print(f"Avogreen Printer Connector démarré")
    print(f"Imprimante: {ZEBRA_IP}:{ZEBRA_PORT}")
    print(f"Proxy: 0.0.0.0:{PROXY_PORT}")
    print(f"Logs: /var/log/avogreen-printer.log")
    run_server()
EOF

# Rendre le script exécutable
chmod +x printer_connector.py

# 5. Créer le service systemd
echo "[5/6] Configuration du service systemd..."
cat > "$SERVICE_FILE" << EOF
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

# 6. Configurer le pare-feu
echo "[6/6] Configuration réseau..."
if command -v ufw > /dev/null 2>&1; then
    ufw allow $PROXY_PORT/tcp comment "Avogreen Printer"
    echo "✅ Pare-feu UFW configuré"
elif command -v firewall-cmd > /dev/null 2>&1; then
    firewall-cmd --permanent --add-port=$PROXY_PORT/tcp
    firewall-cmd --reload
    echo "✅ Pare-feu firewalld configuré"
else
    echo "ℹ️  Aucun pare-feu détecté, poursuite de l'installation..."
fi

# 7. Démarrer le service
echo "🔄 Démarrage du service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# 8. Attendre un peu et vérifier
sleep 3

# 9. Afficher le résultat
echo ""
echo "========================================"
echo "✅ INSTALLATION TERMINÉE AVEC SUCCÈS"
echo "========================================"

# Obtenir l'IP publique
PUBLIC_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}' || echo "VOTRE-IP-PUBLIQUE")

echo "📡 URL À FOURNIR À AVOGREEN :"
echo "   http://${PUBLIC_IP}:${PROXY_PORT}"
echo ""
echo "🔍 COMMANDES DE VÉRIFICATION :"
echo "   sudo systemctl status $SERVICE_NAME"
echo "   curl http://localhost:$PROXY_PORT"
echo "   sudo journalctl -u $SERVICE_NAME -f"
echo ""
echo "📝 LOGS :"
echo "   /var/log/avogreen-printer.log"
echo "========================================"

# Vérifier que le service tourne
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✅ Service actif et fonctionnel"
else
    echo "⚠️  Service inactif, vérifiez les logs :"
    journalctl -u "$SERVICE_NAME" -n 20 --no-pager
fi