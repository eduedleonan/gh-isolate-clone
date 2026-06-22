#!/usr/bin/env bash
# Desactivamos momentáneamente 'e' y 'pipefail' en la detección para evitar cierres agresivos por red
set -u

echo "===================================================="
echo "🌍 GH-UNIVERSAL-ORCHESTRATOR: CONFIGURAR O CLONAR"
echo "===================================================="

# 1. Intentar auto-detectar el usuario de GitHub mediante SSH
echo "🔍 Detectando identidad en GitHub..."
DETECTED_USER=""

# Forzamos a SSH a ignorar el tty interactivo y capturamos solo el texto
SSH_REPLY=$(ssh -T -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new git@github.com 2>&1)

if [[ "$SSH_REPLY" =~ Hi[[:space:]]([^!]+)! ]]; then
    DETECTED_USER="${BASH_REMATCH[1]}"
    echo "✅ Identidad detectada: $DETECTED_USER"
else
    echo "⚠️  No se pudo auto-detectar el usuario en este equipo."
fi

# Ahora que pasamos la red, activamos el modo estricto de seguridad para el resto del script
set -eo pipefail

# 2. Solicitar Usuario (Nunca vacío)
if [ -n "$DETECTED_USER" ]; then
    read -p "👤 Usuario de GitHub [$DETECTED_USER]: " GH_USER </dev/tty
    GH_USER="${GH_USER:-$DETECTED_USER}"
else
    read -p "👤 Usuario de GitHub: " GH_USER </dev/tty
    while [ -z "$GH_USER" ]; do
        read -p "❌ El usuario no puede estar vacío: " GH_USER </dev/tty
    done
fi

# 3. DETECCIÓN DE ENTORNO
CANT_ARCHIVOS=$(find . -maxdepth 1 ! -name "." | wc -l)

if [ "$CANT_ARCHIVOS" -eq 0 ]; then
    echo "----------------------------------------------------"
    echo "✨ DETECTADO: Carpeta limpia. Activando MODO CLONACIÓN."
    echo "----------------------------------------------------"
    read -p "📦 Nombre del repositorio remoto a descargar: " REPO_NAME </dev/tty
    while [ -z "$REPO_NAME" ]; do read -p "❌ El nombre no puede estar vacío: " REPO_NAME </dev/tty; done
    
    URL_REMOTA="git@github.com:${GH_USER}/${REPO_NAME}.git"
    echo "⚡ Validando acceso al repositorio remoto..."
    if ! git ls-remote "$URL_REMOTA" &>/dev/null; then
        echo "❌ ERROR: No se encontró el repositorio o tu llave no tiene acceso."
        exit 1
    fi
    echo "📥 Descargando repositorio en la carpeta actual..."
    git clone "$URL_REMOTA" .
    echo "===================================================="
    echo "🎉 ¡Hecho! Repositorio descargado y listo."
    echo "===================================================="
else
    echo "----------------------------------------------------"
    echo "📦 DETECTADO: Carpeta con archivos. Activando MODO RECONSTRUCCIÓN."
    echo "----------------------------------------------------"
    read -p "📦 Nombre del repositorio en GitHub: " REPO_NAME </dev/tty
    while [ -z "$REPO_NAME" ]; do read -p "❌ El nombre no puede estar vacío: " REPO_NAME </dev/tty; done

    URL_REMOTA="git@github.com:${GH_USER}/${REPO_NAME}.git"
    echo "⚡ Validando existencia en GitHub..."
    if ! git ls-remote "$URL_REMOTA" &>/dev/null; then
        echo "❌ ERROR DE VALIDACIÓN: No se pudo acceder a $URL_REMOTA"
        exit 1
    fi

    if [ -d ".git" ]; then
        echo "🗑️  Limpiando Git anterior (.git)..."
        rm -rf .git
    fi

    echo "🏗️  Inicializando Git local..."
    git init &>/dev/null
    git branch -M main
    git remote add origin "$URL_REMOTA"
    echo "✍️  Creando commit inicial (Firma automática --global)..."
    git add .
    git commit -m "Initial Commit: Repositorio universal configurado"
    echo "🚀 Subiendo cambios a GitHub..."
    git push -u origin main --force
    echo "===================================================="
    echo "🎉 ¡Todo listo! Repositorio sincronizado."
    echo "===================================================="
fi
