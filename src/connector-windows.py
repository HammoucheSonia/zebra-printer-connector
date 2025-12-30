#!/usr/bin/env python3
"""
Connecteur Avogreen - Version Windows
"""

import socket
import json
import logging
import time
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

# Chemin de configuration Windows
if hasattr(sys, '_MEIPASS'):  # PyInstaller
    CONFIG_FILE = os.path.join(sys._MEIPASS, "config.json")
else:
    CONFIG_FILE = os.path.join(os.path.dirname(__file__), "config.json")

# Charger configuration
try:
    with open(CONFIG_FILE, 'r') as f:
        config = json.load(f)
    
    PRINTER_IP = config['printer_ip']
    PRINTER_PORT = config['printer_port']
    AUTH_TOKEN = config['auth_token']
    CONNECTOR_PORT = config.get('connector_port', 9090)
    
except Exception as e:
    print(f"ERREUR Configuration: {e}")
    print(f"Fichier: {CONFIG_FILE}")
    sys.exit(1)

# Logging Windows
LOG_FILE = os.path.join(os.path.dirname(__file__), "avogreen-printer.log")
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class PrinterHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        """Reçoit les commandes d'impression depuis Avogreen"""
        auth_header = self.headers.get('Authorization')
        if not auth_header or auth_header != f"Bearer {AUTH_TOKEN}":
            self.send_response(401)
            self.end_headers()
            return
        
        content_length = int(self.headers['Content-Length'])
        zpl_data = self.rfile.read(content_length)
        
        logger.info(f"Commande reçue - {len(zpl_data)} bytes")
        
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
        """Endpoints de santé"""
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            printer_ok = self.test_printer()
            status = {
                "status": "healthy" if printer_ok else "warning",
                "service": "avogreen-printer-connector",
                "os": "windows",
                "printer_connected": printer_ok,
                "timestamp": time.time()
            }
            self.wfile.write(json.dumps(status).encode())
        
        elif self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(b"<h1>Avogreen Printer Connector Windows</h1><p>Service actif</p>")
        
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
    server = HTTPServer(('0.0.0.0', CONNECTOR_PORT), PrinterHandler)
    
    logger.info(f"Connecteur Windows démarré sur le port {CONNECTOR_PORT}")
    logger.info(f"Imprimante cible: {PRINTER_IP}:{PRINTER_PORT}")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Arrêt du connecteur")
        server.server_close()

if __name__ == '__main__':
    print("=" * 50)
    print("AVOGREEN PRINTER CONNECTOR - WINDOWS")
    print("=" * 50)
    print(f"Imprimante: {PRINTER_IP}:{PRINTER_PORT}")
    print(f"Port API: {CONNECTOR_PORT}")
    print(f"Logs: {LOG_FILE}")
    print("=" * 50)
    
    run_server()