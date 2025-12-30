# 🖨️ Avogreen Zebra Printer Connector

Connecteur automatique pour l'impression en temps réel des étiquettes de commandes Avogreen sur imprimantes Zebra.

## 📋 Fonctionnalités

- **Impression automatique** des étiquettes depuis la plateforme Avogreen
- **Support multiplateforme** : Linux (systemd) et Windows (Service)
- **Configuration interactive** avec prompts guidés
- **Haute disponibilité** : redémarrage automatique
- **Journalisation complète** : logs locaux détaillés

## ⚡ Installation Rapide

### Linux (Ubuntu/Debian/CentOS)
```bash
# Installation en une commande
curl -sSL https://raw.githubusercontent.com/HammoucheSonia/zebra-printer-connector/main/install.sh | sudo bash

Windows (PowerShell Admin)
# Exécuter en tant qu'administrateur
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-windows.ps1

🔧 Configuration
L'installation vous demandera :
Adresse IP de votre imprimante Zebra
Port (par défaut : 9100)
Validation de la configuration réseau

Prérequis
✅ Serveur Linux/Windows avec accès réseau à l'imprimante Zebra
✅ Port 9090 ouvert pour les connexions entrantes

