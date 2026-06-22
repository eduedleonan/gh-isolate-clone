#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo "🌍 GH-UNIVERSAL-PUSH: ORQUESTADOR GLOBAL Y SEGURO"
echo "===================================================="

# 1. Confirmación de seguridad
echo "⚠️  Se configurará el repositorio Git en la carpeta actual:"
echo "   📍 $PWD"
read -p "¿Deseas continuar? (s/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    echo "❌ Operación cancelada."
    exit 0
fi

# 2. Intentar auto-detectar el usuario de GitHub mediante SSH
echo "🔍 Detectando identidad en GitHub..."
DETECTED_USER=""
# Capturamos el saludo de GitHub (ej: "Hi tu_usuario_gh! You've successfully...")
if SSH_REPLY=$(ssh -o ConnectTimeout=5 -T git@github.com 2>&1); then
    : # SSH exit 1 es normal en GitHub, manejamos el texto en el else/comprobación
fi

if [[ "$SSH_REPLY" =~ Hi[[:space:]]([^!]+)! ]]; then
    DETECTED_USER="${BASH_REMATCH[1]}"
    echo "✅ Identidad detectada: $DETECTED_USER"
else
    echo "⚠️  No se pudo auto-detectar el usuario (¿ssh-agent apagado?)."
fi

# 3. Solicitar Datos (Nunca vacíos)
if [ -n "$DETECTED_USER" ]; then
    read -p "👤 Usuario de GitHub [$DETECTED_USER]: " GH_USER
    GH_USER="${GH_USER:-$DETECTED_USER}"
else
    read -p "👤 Usuario de GitHub: " GH_USER
    while [ -z "$GH_USER" ]; do
        read -p "❌ El usuario no puede estar vacío. Introduce tu usuario: " GH_USER
    done
fi

read -p "📦 Nombre del repositorio en GitHub: " REPO_NAME
while [ -z "$REPO_NAME" ]; do
    read -p "❌ El nombre del repositorio no puede estar vacío. Introdúcelo: " REPO_NAME
done

URL_REMOTA="git@github.com:${GH_USER}/${REPO_NAME}.git"

# 4. Validar la URL de manera remota antes de alterar nada
echo "⚡ Validando existencia del repositorio en GitHub..."
if ! git ls-remote "$URL_REMOTA" &>/dev/null; then
    echo ""
    echo "❌ ERROR DE VALIDACIÓN REMOTA:"
    echo "   No se pudo acceder a: $URL_REMOTA"
    echo "   Posibles causas:"
    echo "   1. El repositorio privado/público aún no ha sido creado en la web de GitHub."
    echo "   2. El usuario '$GH_USER' o el repositorio '$REPO_NAME' tienen un error de dedo."
    echo "   3. Tu llave SSH universal no está cargada en el ssh-agent."
    echo ""
    exit 1
fi
echo "✅ ¡Conexión exitosa! El repositorio remoto existe y está listo."

# 5. Limpieza e Inicialización limpia (Solo si la validación remota pasó)
if [ -d ".git" ]; then
    echo "🗑️  Limpiando historial de Git anterior (.git)..."
    rm -rf .git
fi

echo "🏗️  Inicializando nuevo repositorio Git..."
git init &>/dev/null
git branch -M main

echo "🔗 Vinculando origen a la URL validada..."
git remote add origin "$URL_REMOTA"

# 6. Primer Commit y Push Forzado
echo "----------------------------------------------------"
echo "📦 Preparando archivos locales..."
git add .

if git diff --cached --quiet; then
    echo "ℹ️  No hay archivos en la carpeta para subir, pero el entorno Git quedó perfectamente enlazado."
else
    echo "✍️  Creando commit (Firmando con tus reglas --global)..."
    git commit -m "Initial Commit: Repositorio universal inicializado de forma segura"
    
    echo "🚀 Subiendo cambios a GitHub..."
    git push -u origin main --force
    echo "===================================================="
    echo "🎉 ¡Todo listo! Repositorio sincronizado y verificado."
    echo "===================================================="
fi
