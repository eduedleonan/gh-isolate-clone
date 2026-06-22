#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo "🚀 GH-ISOLATE-CLONE: ORQUESTADOR DE SSH Y REPOS      "
echo "===================================================="

# Asegurar entorno SSH base
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
SSH_CONFIG="$HOME/.ssh/config"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

# --- PARTE 1: AUDITORÍA Y MIGRACIÓN DE REPOSITORIOS EXISTENTES ---
echo "🔍 Escaneando la máquina en busca de repositorios Git desprotegidos..."
IFS=$'\n' read -r -d '' -a REPOS_ENCONTRADOS < <(find "$HOME" -maxdepth 3 -name ".git" -type d 2>/dev/null) || true

for git_dir in "${REPOS_ENCONTRADOS[@]}"; do
    repo_path=$(dirname "$git_dir")
    if [ "$repo_path" = "$PWD" ]; then continue; fi
    
    cd "$repo_path"
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "Ninguno")
    
    if [[ "$REMOTE_URL" =~ "git@github.com:" ]]; then
        OTROS_REPO_NAME=$(basename "$repo_path")
        echo "⚠️  Detectado: '$OTROS_REPO_NAME' usa conexión genérica vulnerable."
        read -p "   ¿Deseas aislar este repositorio con su propia llave SSH? (s/n): " BI_ISOLATE
        
        if [[ "$BI_ISOLATE" =~ ^[Ss]$ ]]; then
            NUEVA_LLAVE_EXTRA="$HOME/.ssh/id_ed25519_gh_${OTROS_REPO_NAME}"
            ALIAS_EXTRA="github-${OTROS_REPO_NAME}"
            
            if [ ! -f "$NUEVA_LLAVE_EXTRA" ]; then
                read -p "   📧 Correo para la llave de $OTROS_REPO_NAME: " EXTRA_EMAIL
                ssh-keygen -t ed25519 -C "$EXTRA_EMAIL" -f "$NUEVA_LLAVE_EXTRA" -N ""
                
                cat << EOF >> "$SSH_CONFIG"

# Conexión aislada automática para el proyecto ${OTROS_REPO_NAME}
Host ${ALIAS_EXTRA}
    HostName github.com
    User git
    IdentityFile ${NUEVA_LLAVE_EXTRA}
    IdentitiesOnly yes
EOF
                echo "📋 Llave pública generada para $OTROS_REPO_NAME. Cópiala a tu GitHub:"
                echo "👉 https://github.com"
                cat "${NUEVA_LLAVE_EXTRA}.pub"
                echo "=========================================================================="
                read -p "🎯 Presiona [Enter] cuando la hayas agregado en la web..."
            fi
            
            URL_PART=$(echo "$REMOTE_URL" | cut -d':' -f2)
            git remote set-url origin "git@${ALIAS_EXTRA}:${URL_PART}"
            echo "✅ Repositorio '$OTROS_REPO_NAME' aislado con éxito."
            echo "----------------------------------------------------"
        fi
    fi
done
cd "$PWD"


# --- PARTE 2: CONFIGURACIÓN Y CLONACIÓN DEL NUEVO REPOSITORIO ---
echo "📝 Configuración del nuevo repositorio a clonar"
read -p "👤 Introduce tu usuario de GitHub: " GH_USER
if [ -z "$GH_USER" ]; then
    echo "❌ El usuario de GitHub no puede estar vacío."
    exit 1
fi

read -p "📦 Introduce el nombre del repositorio (ej. predial-installer): " REPO_NAME
if [ -z "$REPO_NAME" ]; then
    echo "❌ El nombre del repositorio no puede estar vacío."
    exit 1
fi

SSH_KEY_PROYECTO="$HOME/.ssh/id_ed25519_gh_${REPO_NAME}"
ALIAS_PROYECTO="github-${REPO_NAME}"

if [ ! -f "$SSH_KEY_PROYECTO" ]; then
    read -p "📧 Introduce tu correo para la llave de $REPO_NAME: " USER_EMAIL
    ssh-keygen -t ed25519 -C "$USER_EMAIL" -f "$SSH_KEY_PROYECTO" -N ""
    
    cat << EOF >> "$SSH_CONFIG"

# Conexión aislada para el proyecto ${REPO_NAME}
Host ${ALIAS_PROYECTO}
    HostName github.com
    User git
    IdentityFile ${SSH_KEY_PROYECTO}
    IdentitiesOnly yes
EOF
    echo "✅ Regla de enrutamiento añadida a SSH Config."
fi

echo ""
echo "🔑 COPIA ESTA LLAVE EXCLUSIVA Y AGRÉGALA A TU CUENTA DE GITHUB:"
echo "👉 https://github.com"
echo "=========================================================================="
cat "${SSH_KEY_PROYECTO}.pub"
echo "=========================================================================="
echo ""
read -p "🎯 Presiona [Enter] una vez que hayas guardado la llave en la web..."

echo "🔄 Validando conexión SSH con el alias seguro..."
ssh -T "git@${ALIAS_PROYECTO}" 2>&1 | grep -q "successfully authenticated" || {
    echo "❌ Error de autenticación. Verifica si guardaste la llave en tu perfil."
    exit 1
}

echo "📥 Clonando '$REPO_NAME' de forma aislada..."
git clone "git@${ALIAS_PROYECTO}:${GH_USER}/${REPO_NAME}.git"

# --- PARTE 3: INYECCIÓN DE IDENTIDAD LOCAL EXCLUSIVA POR PROYECTO ---
if [ -d "$REPO_NAME" ]; then
    cd "$REPO_NAME"
    echo "----------------------------------------------------"
    echo "👤 Configuración de Firma e Identidad Local para este repositorio"
    read -p "❓ ¿Deseas asignar un Nombre/Correo específico solo para este proyecto? (s/n): " LOCAL_CONFIG
    
    if [[ "$LOCAL_CONFIG" =~ ^[Ss]$ ]]; then
        read -p "   👤 Nombre para este proyecto: " LOCAL_NAME
        read -p "   📧 Correo para este proyecto: " LOCAL_EMAIL
        
        # Guardar únicamente en el entorno local (.git/config) de esta carpeta
        git config --local user.name "$LOCAL_NAME"
        git config --local user.email "$LOCAL_EMAIL"
        
        # Forzar firma de commits con la llave SSH del proyecto automáticamente
        git config --local gpg.format ssh
        git config --local user.signingkey "${SSH_KEY_PROYECTO}.pub"
        git config --local commit.gpgsign true
        
        echo "✅ Identidad exclusiva y firmas digitales configuradas localmente."
    else
        echo "⏭️ Se usarán las configuraciones globales de Git de esta máquina."
    fi
fi

echo "===================================================="
echo "🎉 ¡Todo listo! Tu entorno multi-identidad está blindado."
echo "📂 Ingresa al proyecto con: cd $REPO_NAME"
echo "===================================================="
