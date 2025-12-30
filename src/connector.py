#!/usr/bin/env python3
"""
Connecteur d'impression Avogreen - Version simplifiée
"""

import socket
import json
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
import time
import os

# Configuration
CONFIG_FILE = "/etc/avogreen/printer_config.json"

# Charger configuration
with open(CONFIG_FILE, 'r') as f:
    config = json.load(f)

PRINTER_IP = config['printer_ip']
PRINTER_PORT = config['printer_port']
AUTH_TOKEN = config['auth_token']

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/avogreen-printer/connector.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class PrinterHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        """Reçoit les commandes d'impression depuis Avogreen"""
        # Vérifier l'authentification
        auth_header = self.headers.get('Authorization')
        if not auth_header or auth_header != f"Bearer {AUTH_TOKEN}":
            self.send_response(401)
            self.end_headers()
            return
        
        # Lire les données ZPL
        content_length = int(self.headers['Content-Length'])
        zpl_data = self.rfile.read(content_length)
        
        logger.info(f"Commande reçue - {len(zpl_data)} bytes")
        
        # Envoyer à l'imprimante
        success = self.send_to_printer(zpl_data)
        
        if success:
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {"status": "success", "timestamp": time.time()}
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(500)
            self.end_headers()
    
    def do_GET(self):
        """Endpoints de santé et informations"""
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            # Tester la connexion à l'imprimante
            printer_ok = self.test_printer()
            
            status = {
                "status": "healthy" if printer_ok else "warning",
                "service": "avogreen-printer-connector",
                "printer_connected": printer_ok,
                "timestamp": time.time()
            }
            self.wfile.write(json.dumps(status).encode())
        
        elif self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(b"<h1>Avogreen Printer Connector</h1><p>Service actif</p>")
        
        else:
            self.send_response(404)
            self.end_headers()
    
    def send_to_printer(self, zpl_data):
        """Envoie les données à l'imprimante Zebra"""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(10)
                s.connect((PRINTER_IP, PRINTER_PORT))
                s.sendall(zpl_data)
                logger.info(f"Imprimante sur {PRINTER_IP}:{PRINTER_PORT}")
                return True
        except Exception as e:
            logger.error(f"Erreur impression: {str(e)}")
            return False
    
    def test_printer(self):
        """Teste la connexion à l'imprimante"""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(3)
                s.connect((PRINTER_IP, PRINTER_PORT))
                return True
        except:
            return False
    
    def log_message(self, format, *args):
        logger.info(format % args)

def run_server():
    """Démarre le serveur"""
    port = config.get('connector_port', 9090)
    server = HTTPServer(('0.0.0.0', port), PrinterHandler)
    
    logger.info(f"Connecteur démarré sur le port {port}")
    logger.info(f"Imprimante cible: {PRINTER_IP}:{PRINTER_PORT}")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Arrêt du connecteur")
        server.server_close()

if __name__ == '__main__':
    print("Avogreen Printer Connector")
    print(f"Imprimante: {PRINTER_IP}:{PRINTER_PORT}")
    print(f"Port: {config.get('connector_port', 9090)}")
    run_server()