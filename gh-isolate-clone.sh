#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo "🚀 GH-ISOLATE-CLONE: ORQUESTADOR DE SSH Y FIRMAS"
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
        read -p "   ¿Deseas aislar y activar firma verificada para este repositorio? (s/n): " BI_ISOLATE
        
        if [[ "$BI_ISOLATE" =~ ^[Ss]$ ]]; then
            NUEVA_LLAVE_EXTRA="$HOME/.ssh/id_ed25519_gh_${OTROS_REPO_NAME}"
            ALIAS_EXTRA="github-${OTROS_REPO_NAME}"
            
            if [ ! -f "$NUEVA_LLAVE_EXTRA" ]; then
                read -p "    📧 Correo/Email configurado en GitHub para $OTROS_REPO_NAME: " EXTRA_EMAIL
                ssh-keygen -t ed25519 -C "$EXTRA_EMAIL" -f "$NUEVA_LLAVE_EXTRA" -N ""
                
                cat << EOF >> "$SSH_CONFIG"

# Conexión aislada automática para el proyecto ${OTROS_REPO_NAME}
Host ${ALIAS_EXTRA}
    HostName github.com
    User git
    IdentityFile ${NUEVA_LLAVE_EXTRA}
    IdentitiesOnly yes
EOF
                echo "📋 IMPORTANTE: Sube esta llave a GitHub con Tipo 'Signing Key' e 'Authentication Key':"
                echo "👉 https://github.com/settings/keys"
                echo "=========================================================================="
                cat "${NUEVA_LLAVE_EXTRA}.pub"
                echo "=========================================================================="
                read -p "🎯 Presiona [Enter] cuando la hayas agregado (ambas veces si aplica) en la web..."
                
                # Registrar en allowed_signers local para evitar alertas en la terminal
                echo "$EXTRA_EMAIL $(cat "${NUEVA_LLAVE_EXTRA}.pub")" >> "$ALLOWED_SIGNERS"
            else
                # Si la llave ya existía, recuperamos el email asignado a ella
                EXTRA_EMAIL=$(ssh-keygen -l -f "$NUEVA_LLAVE_EXTRA" | awk '{print $NF}')
            fi
            
            # Reconfigurar conexión remota por el alias
            URL_PART=$(echo "$REMOTE_URL" | cut -d':' -f2)
            git remote set-url origin "git@${ALIAS_EXTRA}:${URL_PART}"
            
            # INYECCIÓN DE FIRMA DIGITAL LOCAL EN EL REPOSITORIO ANTIGUO
            git config --local gpg.format ssh
            git config --local user.signingkey "${NUEVA_LLAVE_EXTRA}.pub"
            git config --local commit.gpgsign true
            git config --local gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"
            if [ -n "$EXTRA_EMAIL" ]; then git config --local user.email "$EXTRA_EMAIL"; fi
            
            echo "✅ Repositorio '$OTROS_REPO_NAME' aislado y firmas SSH activadas con éxito."
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
USER_EMAIL=""

if [ ! -f "$SSH_KEY_PROYECTO" ]; then
    read -p "📧 Introduce el correo exacto de tu cuenta de GitHub para este proyecto: " USER_EMAIL
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
    
    # Registrar en el archivo general de confianza local
    echo "$USER_EMAIL $(cat "${SSH_KEY_PROYECTO}.pub")" >> "$ALLOWED_SIGNERS"
else
    USER_EMAIL=$(ssh-keygen -l -f "$SSH_KEY_PROYECTO" | awk '{print $NF}')
fi

echo ""
echo "🔑 REGISTRA ESTA LLAVE DOS VECES EN GITHUB (Como Authentication Y Como Signing Key):"
echo "👉 https://github.com/settings/keys"
echo "=========================================================================="
cat "${SSH_KEY_PROYECTO}.pub"
echo "=========================================================================="
echo ""
read -p "🎯 Presiona [Enter] una vez que hayas guardado AMBAS configuraciones en la web..."

echo "🔄 Validando conexión SSH con el alias seguro..."
# Se fuerza el uso de la opción estricta para probar el alias
ssh -o "IdentitiesOnly=yes" -F "$SSH_CONFIG" -T "git@${ALIAS_PROYECTO}" 2>&1 | grep -q "successfully authenticated" || {
    echo "❌ Error de autenticación. Verifica si guardaste la llave en tu perfil de GitHub."
    exit 1
}

echo "📥 Clonando '$REPO_NAME' de forma aislada en el directorio superior..."
# Clonamos apuntando a la ruta un nivel arriba (../$REPO_NAME)
git clone "git@${ALIAS_PROYECTO}:${GH_USER}/${REPO_NAME}.git" "../${REPO_NAME}"

# --- PARTE 3: INYECCIÓN DE IDENTIDAD Y CONFIGURACIÓN DE FIRMA ---
if [ -d "$REPO_NAME" ]; then
    cd "$REPO_NAME"
    echo "----------------------------------------------------"
    echo "👤 Configuración de Firma e Identidad Local para este repositorio"
    
    # Forzar el correo asociado a la llave para asegurar el "Verified"
    git config --local user.email "$USER_EMAIL"
    
    read -p "👤 Nombre/Alias para mostrar en los commits de este proyecto: " LOCAL_NAME
    if [ -n "$LOCAL_NAME" ]; then
        git config --local user.name "$LOCAL_NAME"
    fi
    
    # Configuración estricta de Firma SSH Local
    git config --local gpg.format ssh
    git config --local user.signingkey "${SSH_KEY_PROYECTO}.pub"
    git config --local commit.gpgsign true
    git config --local gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"
    
    echo "✅ Identidad exclusiva, enrutamiento y FIRMA DIGITAL SSH configurados con éxito."
fi

echo "===================================================="
echo "🎉 ¡Todo listo! Tu entorno multi-identidad firmado está operativo."
echo "📂 Ingresa al proyecto con: cd $REPO_NAME"
echo "===================================================="

