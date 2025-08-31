#!/bin/bash

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔐 AWS Credentials Handler for Steampipe${NC}"
echo "========================================"

# Detectar sistema operativo
detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "linux";;
        Darwin*)    echo "macos";;
        CYGWIN*)    echo "windows";;
        MINGW*)     echo "windows";;
        MSYS*)      echo "windows";;
        *)          echo "unknown";;
    esac
}

OS=$(detect_os)
echo -e "📍 Sistema operativo detectado: ${YELLOW}$OS${NC}"

# Variables para credenciales
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_SESSION_TOKEN=""
AWS_REGION=""
AWS_PROFILE="default"

# Función para leer archivos AWS (Linux/macOS)
read_aws_files() {
    local aws_dir="$1"
    
    if [[ ! -d "$aws_dir" ]]; then
        echo -e "${YELLOW}⚠️  Directorio $aws_dir no encontrado${NC}"
        return 1
    fi
    
    local credentials_file="$aws_dir/credentials"
    local config_file="$aws_dir/config"
    
    echo -e "🔍 Buscando archivos AWS en: ${YELLOW}$aws_dir${NC}"
    
    # Leer credentials
    if [[ -f "$credentials_file" ]]; then
        echo -e "✅ Encontrado: ${GREEN}$credentials_file${NC}"
        
        # Usar awk para extraer credenciales del profile
        AWS_ACCESS_KEY_ID=$(awk -F'=' -v profile="$AWS_PROFILE" '
            $0 ~ "\\[" profile "\\]" { found=1; next }
            found && /^\[/ { found=0 }
            found && /aws_access_key_id/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }
        ' "$credentials_file")
        
        AWS_SECRET_ACCESS_KEY=$(awk -F'=' -v profile="$AWS_PROFILE" '
            $0 ~ "\\[" profile "\\]" { found=1; next }
            found && /^\[/ { found=0 }
            found && /aws_secret_access_key/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }
        ' "$credentials_file")
        
        AWS_SESSION_TOKEN=$(awk -F'=' -v profile="$AWS_PROFILE" '
            $0 ~ "\\[" profile "\\]" { found=1; next }
            found && /^\[/ { found=0 }
            found && /aws_session_token/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }
        ' "$credentials_file")
    else
        echo -e "${YELLOW}⚠️  No se encontró $credentials_file${NC}"
    fi
    
    # Leer config para región
    if [[ -f "$config_file" ]]; then
        echo -e "✅ Encontrado: ${GREEN}$config_file${NC}"
        
        AWS_REGION=$(awk -F'=' -v profile="profile $AWS_PROFILE" '
            $0 ~ "\\[" profile "\\]" { found=1; next }
            found && /^\[/ { found=0 }
            found && /region/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }
        ' "$config_file")
        
        # Si es el profile default, también buscar sin "profile"
        if [[ "$AWS_PROFILE" == "default" && -z "$AWS_REGION" ]]; then
            AWS_REGION=$(awk -F'=' '
                /^\[default\]/ { found=1; next }
                found && /^\[/ { found=0 }
                found && /region/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }
            ' "$config_file")
        fi
    else
        echo -e "${YELLOW}⚠️  No se encontró $config_file${NC}"
    fi
}

# Función para leer variables de entorno según el OS
read_env_variables() {
    echo -e "🔍 Verificando variables de entorno..."
    
    case "$OS" in
        "linux"|"macos")
            [[ -n "$AWS_ACCESS_KEY_ID" ]] || AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
            [[ -n "$AWS_SECRET_ACCESS_KEY" ]] || AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
            [[ -n "$AWS_SESSION_TOKEN" ]] || AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"
            [[ -n "$AWS_REGION" ]] || AWS_REGION="${AWS_REGION:-$AWS_DEFAULT_REGION}"
            ;;
        "windows")
            # En Windows, usar variables de entorno del sistema
            [[ -n "$AWS_ACCESS_KEY_ID" ]] || AWS_ACCESS_KEY_ID=$(cmd.exe /c "echo %AWS_ACCESS_KEY_ID%" 2>/dev/null | tr -d '\r\n')
            [[ -n "$AWS_SECRET_ACCESS_KEY" ]] || AWS_SECRET_ACCESS_KEY=$(cmd.exe /c "echo %AWS_SECRET_ACCESS_KEY%" 2>/dev/null | tr -d '\r\n')
            [[ -n "$AWS_SESSION_TOKEN" ]] || AWS_SESSION_TOKEN=$(cmd.exe /c "echo %AWS_SESSION_TOKEN%" 2>/dev/null | tr -d '\r\n')
            [[ -n "$AWS_REGION" ]] || AWS_REGION=$(cmd.exe /c "echo %AWS_REGION%" 2>/dev/null | tr -d '\r\n')
            ;;
    esac
}

# Función para generar session token usando STS
generate_session_token() {
    echo -e "🔄 Generando session token temporal (1 hora)..."
    
    if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
        echo -e "${RED}❌ Error: AWS_ACCESS_KEY_ID y AWS_SECRET_ACCESS_KEY son requeridos${NC}"
        return 1
    fi
    
    # Verificar si aws cli está disponible
    if ! command -v aws >/dev/null 2>&1; then
        echo -e "${RED}❌ Error: AWS CLI no está instalado${NC}"
        return 1
    fi
    
    # Generar credenciales temporales
    local sts_output
    sts_output=$(AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
                 AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
                 aws sts get-session-token \
                 --duration-seconds 3600 \
                 --output json 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Error: No se pudo generar session token${NC}"
        return 1
    fi
    
    # Extraer credenciales del JSON
    AWS_ACCESS_KEY_ID=$(echo "$sts_output" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)
    AWS_SECRET_ACCESS_KEY=$(echo "$sts_output" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)
    AWS_SESSION_TOKEN=$(echo "$sts_output" | grep -o '"SessionToken": "[^"]*"' | cut -d'"' -f4)
    
    echo -e "${GREEN}✅ Session token generado exitosamente${NC}"
}

# Función principal
main() {
    # Leer profile si se especifica
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        echo -e "🎯 Usando AWS Profile: ${YELLOW}$AWS_PROFILE${NC}"
    fi
    
    # 1. Intentar leer archivos AWS primero
    case "$OS" in
        "linux"|"macos")
            read_aws_files "$HOME/.aws"
            ;;
        "windows")
            # En Windows, intentar tanto la ruta de usuario como %USERPROFILE%
            if [[ -d "$HOME/.aws" ]]; then
                read_aws_files "$HOME/.aws"
            elif [[ -n "${USERPROFILE:-}" && -d "$USERPROFILE/.aws" ]]; then
                read_aws_files "$USERPROFILE/.aws"
            fi
            ;;
    esac
    
    # 2. Completar con variables de entorno si faltan datos
    read_env_variables
    
    # 3. Mostrar estado de las credenciales encontradas
    echo ""
    echo -e "${GREEN}📋 Estado de credenciales:${NC}"
    echo -e "AWS_ACCESS_KEY_ID: ${YELLOW}$([ -n "$AWS_ACCESS_KEY_ID" ] && echo "✅ Encontrado" || echo "❌ Faltante")${NC}"
    echo -e "AWS_SECRET_ACCESS_KEY: ${YELLOW}$([ -n "$AWS_SECRET_ACCESS_KEY" ] && echo "✅ Encontrado" || echo "❌ Faltante")${NC}"
    echo -e "AWS_SESSION_TOKEN: ${YELLOW}$([ -n "$AWS_SESSION_TOKEN" ] && echo "✅ Encontrado" || echo "❌ No necesario")${NC}"
    echo -e "AWS_REGION: ${YELLOW}$([ -n "$AWS_REGION" ] && echo "✅ $AWS_REGION" || echo "❌ Usando us-east-1 por defecto")${NC}"
    
    # 4. Si no hay session token, generar uno
    if [[ -z "$AWS_SESSION_TOKEN" && -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]]; then
        echo ""
        generate_session_token
    fi
    
    # 5. Validar que tenemos las credenciales mínimas
    if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
        echo -e "${RED}❌ Error: No se pudieron obtener credenciales AWS válidas${NC}"
        exit 1
    fi
    
    # 6. Configurar región por defecto si no existe
    [[ -z "$AWS_REGION" ]] && AWS_REGION="us-east-1"
    
    # 7. Exportar variables para el contenedor
    echo ""
    echo -e "${GREEN}🚀 Exportando variables para Docker...${NC}"
    
    # Crear archivo temporal con las variables
    cat > /tmp/aws_env_vars << EOF
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
AWS_REGION=$AWS_REGION
EOF
    
    echo -e "${GREEN}✅ Variables exportadas a /tmp/aws_env_vars${NC}"
    echo ""
    echo -e "${YELLOW}💡 Para usar en Docker:${NC}"
    echo "docker run --env-file /tmp/aws_env_vars your-steampipe-image"
    
    return 0
}

# Ejecutar función principal
main "$@"