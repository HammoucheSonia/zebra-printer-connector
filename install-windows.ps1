# Script d'installation PowerShell pour Windows
Write-Host "=== Installation Avogreen Printer Connector Windows ==="

# Vérifier admin
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERREUR: Exécutez en tant qu'Administrateur!" -ForegroundColor Red
    exit
}

# Créer répertoire
$installDir = "C:\AvogreenPrinter"
New-Item -ItemType Directory -Force -Path $installDir

# Télécharger le connecteur
$connectorUrl = "https://raw.githubusercontent.com/HammoucheSonia/zebra-printer-connector/main/src/connector-windows.py"
Invoke-WebRequest -Uri $connectorUrl -OutFile "$installDir\connector.py"

# Créer configuration
$printerIp = Read-Host "IP imprimante Zebra [192.168.1.22]"
if (-not $printerIp) { $printerIp = "192.168.1.22" }

$config = @{
    printer_ip = $printerIp
    printer_port = 9100
    auth_token = "windows-$(Get-Date -Format 'yyyyMMddHHmmss')"
    connector_port = 9090
} | ConvertTo-Json -Depth 3

$config | Out-File -FilePath "$installDir\config.json" -Encoding UTF8

# Créer script de démarrage
@"
@echo off
cd /d "$installDir"
python connector.py
"@ | Out-File -FilePath "$installDir\start-connector.bat" -Encoding ASCII

Write-Host "✅ Installation terminée!" -ForegroundColor Green
Write-Host "Répertoire: $installDir" -ForegroundColor Yellow