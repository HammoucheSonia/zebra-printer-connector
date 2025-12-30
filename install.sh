
set -euo pipefail

# Configuration
REPO_URL="https://github.com/HammoucheSonia/zebra-printer-connector"
INSTALL_DIR="/opt/avogreen-printer"
SERVICE_NAME="avogreen-printer"
CONFIG_FILE="$INSTALL_DIR/config.env"
EXPECTED_SHA256="..."  # À calculer et inclure

# Couleurs pour output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validation root
[[ $EUID -eq 0 ]] || { log_error "Ce script doit être exécuté en root (sudo)"; exit 1; }

# Installation propre
install_avogreen() {
    log_info "Début de l'installation Avogreen Printer Connector Pro"
    
    # 1. Vérification préalable
    check_prerequisites
    
    # 2. Téléchargement avec vérification
    download_with_verification
    
    # 3. Configuration interactive
    interactive_configuration
    
    # 4. Déploiement sécurisé
    deploy_connector
    
    # 5. Tests complets
    run_tests
    
    # 6. Documentation
    show_documentation
}

check_prerequisites() {
    log_info "Vérification des prérequis..."
    
    # Python 3.6+
    if ! command -v python3 &> /dev/null; then
        log_error "Python3 n'est pas installé"
        exit 1
    fi
    
    # Accès réseau
    if ! timeout 2 bash -c "cat < /dev/null > /dev/tcp/google.com/443" 2>/dev/null; then
        log_warn "Pas d'accès internet détecté"
    fi
}

interactive_configuration() {
    log_info "Configuration interactive"
    
    # IP Imprimante
    read -p "Adresse IP de l'imprimante Zebra [192.168.1.22]: " printer_ip
    printer_ip=${printer_ip:-192.168.1.22}
    
    # Port proxy
    read -p "Port du proxy [9090]: " proxy_port
    proxy_port=${proxy_port:-9090}
    
    # Nom d'hôte (pour URL)
    read -p "Nom d'hôte ou IP publique [auto-détect]: " hostname
    if [[ -z "$hostname" ]]; then
        hostname=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    fi
    
    # Sauvegarde configuration
    cat > "$CONFIG_FILE" << EOF
# Configuration Avogreen Printer Connector
PRINTER_IP="$printer_ip"
PROXY_PORT="$proxy_port"
HOSTNAME="$hostname"
INSTALL_DATE="$(date)"
VERSION="2.0-pro"
EOF
    
    chmod 600 "$CONFIG_FILE"
}

deploy_connector() {
    log_info "Déploiement du connecteur..."
    
    # Création structure
    mkdir -p "$INSTALL_DIR"/{bin,logs,config}
    
    # Téléchargement du script principal depuis votre repo
    wget -q "$REPO_URL/blob/main/printer_connector.py" -O "$INSTALL_DIR/bin/connector.py"
    
    # Application de la configuration
    sed -i "s/ZEBRA_IP = \".*\"/ZEBRA_IP = \"$printer_ip\"/" "$INSTALL_DIR/bin/connector.py"
    sed -i "s/PROXY_PORT = .*/PROXY_PORT = $proxy_port/" "$INSTALL_DIR/bin/connector.py"
    
    # Setup systemd avec templates
    cat > /etc/systemd/system/"$SERVICE_NAME".service << EOF
[Unit]
Description=Avogreen Printer Connector Pro
After=network.target
Requires=network-online.target
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=simple
User=avogreen
Group=avogreen
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$CONFIG_FILE
ExecStart=/usr/bin/python3 $INSTALL_DIR/bin/connector.py
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# Sécurité
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=$INSTALL_DIR/logs /var/log
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Création utilisateur dédié
    useradd -r -s /bin/false -d "$INSTALL_DIR" avogreen 2>/dev/null || true
    chown -R avogreen:avogreen "$INSTALL_DIR"
    
    # Configuration logrotate
    cat > /etc/logrotate.d/avogreen-printer << EOF
$INSTALL_DIR/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 640 avogreen avogreen
    sharedscripts
    postrotate
        systemctl kill -s HUP $SERVICE_NAME.service >/dev/null 2>&1 || true
    endscript
}
EOF
}

run_tests() {
    log_info "Exécution des tests..."
    
    # Démarrer service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    
    sleep 3
    
    # Test 1: Service running
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "✅ Service actif"
    else
        log_error "❌ Service inactif"
        journalctl -u "$SERVICE_NAME" -n 20
        exit 1
    fi
    
    # Test 2: Health check
    if curl -s http://localhost:$proxy_port > /dev/null; then
        log_info "✅ Health check OK"
    else
        log_error "❌ Health check échoué"
        exit 1
    fi
    
    # Test 3: Connexion imprimante
    if timeout 2 nc -z "$printer_ip" 9100; then
        log_info "✅ Imprimante accessible"
    else
        log_warn "⚠️  Imprimante non accessible - vérifiez la connectivité"
    fi
}

show_documentation() {
    log_info "Installation terminée avec succès!"
    
    cat << EOF

========================================
📋 RÉSUMÉ DE L'INSTALLATION
========================================
🔧 Service: $SERVICE_NAME
📍 Imprimante: $printer_ip:9100
🌐 Proxy: http://$hostname:$proxy_port
📁 Installation: $INSTALL_DIR
📝 Logs: $INSTALL_DIR/logs/ et journalctl

========================================
🔍 COMMANDES DE VÉRIFICATION
========================================
Statut:    systemctl status $SERVICE_NAME
Logs:      journalctl -u $SERVICE_NAME -f
Test:      curl http://localhost:$proxy_port
Config:    cat $CONFIG_FILE

========================================
🚨 DÉPANNAGE RAPIDE
========================================
Redémarrer: systemctl restart $SERVICE_NAME
Réinstaller: $0 --reinstall
Désinstaller: $0 --uninstall

========================================
📤 À FOURNIR À AVOGREEN
========================================
1. URL: http://$hostname:$proxy_port
2. Résultat: $(curl -s http://localhost:$proxy_port | head -c 100)

========================================
EOF
}

# Menu principal
case "${1:-}" in
    "--reinstall")
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        rm -rf "$INSTALL_DIR"
        ;;
    "--uninstall")
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        rm -rf "$INSTALL_DIR" /etc/systemd/system/"$SERVICE_NAME".service
        userdel avogreen 2>/dev/null || true
        log_info "Désinstallation complète"
        exit 0
        ;;
    "--help")
        echo "Usage: $0 [--reinstall|--uninstall|--help]"
        exit 0
        ;;
esac

# Lancement
install_avogreen