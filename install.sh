#!/bin/bash
# ===========================================================================
# Avogreen Zebra Printer Connector - Installation Script
# Version: 1.0
# ===========================================================================

set -e  # Arrêter en cas d'erreur

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonctions d'affichage
success() { echo -e "${GREEN}✓ $1${NC}"; }
error() { echo -e "${RED}✗ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
info() { echo -e "ℹ $1"; }

# En-tête
echo "==============================================="
echo "  Installation Avogreen Printer Connector"
echo "==============================================="

# Vérifier root
if [[ $EUID -ne 0 ]]; then
    error "Ce script doit être exécuté en tant que root (sudo)"
    echo "Utilisation: sudo ./install.sh"
    exit 1
fi

# Variables
INSTALL_DIR="/opt/avogreen-printer"
SERVICE_NAME="avogreen-printer-connector"
CONFIG_DIR="/etc/avogreen"
LOG_DIR="/var/log/avogreen-printer"

# ===========================================================================
# ÉTAPE 1: Vérification des prérequis
# ===========================================================================
info "Vérification des prérequis..."

# Vérifier Python 3
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    success "Python $PYTHON_VERSION détecté"
else
    warning "Python 3 n'est pas installé"
    info "Installation de Python 3..."
    
    # Détecter la distribution
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y python3 python3-pip
    elif command -v yum &> /dev/null; then
        yum install -y python3 python3-pip
    elif command -v dnf &> /dev/null; then
        dnf install -y python3 python3-pip
    else
        error "Impossible d'installer Python 3 automatiquement"
        echo "Veuillez installer Python 3 manuellement et relancer le script"
        exit 1
    fi
    success "Python 3 installé"
fi

# ===========================================================================
# ÉTAPE 2: Création des répertoires
# ===========================================================================
info "Création des répertoires..."

for dir in "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$INSTALL_DIR/backup"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        chmod 755 "$dir"
        success "Répertoire créé: $dir"
    fi
done

# ===========================================================================
# ÉTAPE 3: Téléchargement des fichiers
# ===========================================================================
info "Téléchargement des fichiers..."

cd "$INSTALL_DIR"

# Télécharger le connecteur principal
if [[ ! -f "connector.py" ]]; then
    info "Téléchargement du connecteur..."
    wget -q https://raw.githubusercontent.com/avogreen-tech/zebra-printer-connector/main/src/connector.py -O connector.py
    success "Connecteur téléchargé"
else
    warning "Connecteur déjà présent, sauvegarde..."
    cp connector.py backup/connector.py.backup.$(date +%Y%m%d_%H%M%S)
fi

# ===========================================================================
# ÉTAPE 4: Installation des dépendances Python
# ===========================================================================
info "Installation des dépendances..."

pip3 install flask requests --quiet
success "Dépendances installées"

# ===========================================================================
# ÉTAPE 5: Configuration de l'imprimante
# ===========================================================================
echo ""
echo "==============================================="
echo "  CONFIGURATION DE L'IMPRIMANTE ZEBRA"
echo "==============================================="

# Demander l'IP de l'imprimante
DEFAULT_IP="192.168.1.22"
read -p "Adresse IP de votre imprimante Zebra [$DEFAULT_IP]: " PRINTER_IP
PRINTER_IP=${PRINTER_IP:-$DEFAULT_IP}

# Tester la connexion à l'imprimante
info "Test de connexion à l'imprimante $PRINTER_IP:9100..."
if timeout 2 bash -c "cat < /dev/null > /dev/tcp/$PRINTER_IP/9100" 2>/dev/null; then
    success "Imprimante accessible"
else
    warning "Imprimante inaccessible - vérifiez:"
    echo "  1. L'imprimante est allumée"
    echo "  2. L'adresse IP $PRINTER_IP est correcte"
    echo "  3. Le port 9100 n'est pas bloqué par un pare-feu"
    read -p "Continuer malgré tout ? (o/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Oo]$ ]]; then
        error "Installation annulée"
        exit 1
    fi
fi

# ===========================================================================
# ÉTAPE 6: Création du fichier de configuration
# ===========================================================================
info "Création de la configuration..."

# Générer un token d'authentification
AUTH_TOKEN=$(openssl rand -hex 24)

cat > "$CONFIG_DIR/printer_config.json" << EOF
{
  "printer": {
    "ip": "$PRINTER_IP",
    "port": 9100,
    "timeout": 10
  },
  "connector": {
    "port": 9090,
    "host": "0.0.0.0"
  },
  "security": {
    "auth_token": "$AUTH_TOKEN",
    "allowed_ips": ["65.39.73.84"]
  },
  "logging": {
    "level": "INFO",
    "file": "$LOG_DIR/connector.log"
  }
}
EOF

chmod 600 "$CONFIG_DIR/printer_config.json"
success "Configuration créée: $CONFIG_DIR/printer_config.json"

# ===========================================================================
# ÉTAPE 7: Configuration du service systemd
# ===========================================================================
info "Configuration du service systemd..."

cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Avogreen Zebra Printer Connector
After=network.target
Requires=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/connector.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Sécurité
ProtectSystem=strict
ReadWritePaths=$LOG_DIR $CONFIG_DIR

[Install]
WantedBy=multi-user.target
EOF

# Recharger systemd
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

success "Service systemd configuré"

# ===========================================================================
# ÉTAPE 8: Configuration du pare-feu (optionnel)
# ===========================================================================
info "Configuration du pare-feu..."

if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    ufw allow 9090/tcp comment "Avogreen Printer Connector"
    success "Port 9090 ouvert avec ufw"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=9090/tcp
    firewall-cmd --reload
    success "Port 9090 ouvert avec firewalld"
else
    warning "Aucun firewall actif détecté"
    info "Assurez-vous que le port 9090 est accessible"
fi

# ===========================================================================
# ÉTAPE 9: Démarrage et test du service
# ===========================================================================
info "Démarrage du service..."

systemctl start "$SERVICE_NAME"
sleep 3  # Attendre que le service démarre

# Vérifier si le service tourne
if systemctl is-active --quiet "$SERVICE_NAME"; then
    success "Service démarré avec succès"
else
    error "Échec du démarrage du service"
    echo "Derniers logs:"
    journalctl -u "$SERVICE_NAME" --no-pager -n 20
    exit 1
fi

# Tester l'endpoint de santé
info "Test de l'endpoint de santé..."
sleep 2

if curl -s http://localhost:9090/health > /dev/null; then
    success "Connecteur fonctionnel"
else
    warning "L'endpoint de santé ne répond pas"
    info "Vérification des logs..."
    journalctl -u "$SERVICE_NAME" --no-pager -n 10
fi

# ===========================================================================
# ÉTAPE 10: Génération du rapport d'installation
# ===========================================================================
info "Génération du rapport d'installation..."

# Obtenir l'IP publique
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me || echo "NON_DISPONIBLE")

cat > "$INSTALL_DIR/installation_report.txt" << EOF
================================================
RAPPORT D'INSTALLATION - AVOGREEN PRINTER CONNECTOR
================================================
Date: $(date)
Service: $SERVICE_NAME

CONFIGURATION:
- Imprimante: $PRINTER_IP:9100
- Connecteur: Port 9090
- Token: $AUTH_TOKEN

RÉSEAU:
- IP Publique: $PUBLIC_IP
- URL Connecteur: http://$PUBLIC_IP:9090
- IP Avogreen: 65.39.73.84 (autorisée)

FICHIERS:
- Installation: $INSTALL_DIR
- Configuration: $CONFIG_DIR/printer_config.json
- Logs: $LOG_DIR/connector.log
- Service: /etc/systemd/system/$SERVICE_NAME.service

COMMANDES UTILES:
- Statut: systemctl status $SERVICE_NAME
- Logs: journalctl -u $SERVICE_NAME -f
- Redémarrer: systemctl restart $SERVICE_NAME
- Santé: curl http://localhost:9090/health

INFORMATIONS À FOURNIR À AVOGREEN:
1. URL: http://$PUBLIC_IP:9090
2. Token: $AUTH_TOKEN

================================================
EOF

success "Rapport généré: $INSTALL_DIR/installation_report.txt"

# ===========================================================================
# ÉTAPE 11: Affichage des informations finales
# ===========================================================================
echo ""
echo "==============================================="
echo "  INSTALLATION TERMINÉE AVEC SUCCÈS"
echo "==============================================="
echo ""
echo "📡 INFORMATIONS IMPORTANTES:"
echo ""
echo "1. URL À FOURNIR À AVOGREEN:"
echo "   http://$PUBLIC_IP:9090"
echo ""
echo "2. TOKEN D'AUTHENTIFICATION:"
echo "   $AUTH_TOKEN"
echo ""
echo "3. TEST DE FONCTIONNEMENT:"
echo "   curl http://localhost:9090/health"
echo ""
echo "🔧 GESTION DU SERVICE:"
echo "   sudo systemctl status $SERVICE_NAME"
echo "   sudo systemctl restart $SERVICE_NAME"
echo "   sudo journalctl -u $SERVICE_NAME -f"
echo ""
echo "📋 RAPPORT COMPLET:"
echo "   cat $INSTALL_DIR/installation_report.txt"
echo ""
echo "⚠️  ACTION REQUISE:"
echo "   1. Envoyez l'URL et le token à support@avogreen.com"
echo "   2. Nous configurerons votre compte pour l'impression automatique"
echo ""
echo "==============================================="

# Message final
info "L'installation est terminée. Votre connecteur est prêt à recevoir"
info "les commandes d'impression depuis la plateforme Avogreen."
echo ""