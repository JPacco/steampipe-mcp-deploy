#!/bin/bash

set -e

AWS_PROFILE="${AWS_PROFILE:-default}"
OUTPUT_FILE="${1:-/tmp/aws_env_vars}"

echo "AWS Credentials Handler - Profile: $AWS_PROFILE"

# Variables para credenciales
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_SESSION_TOKEN=""
AWS_REGION=""

# Función para leer archivos AWS
read_aws_files() {
    local aws_dir="$1"
    
    if [[ ! -d "$aws_dir" ]]; then
        echo "Directorio $aws_dir no encontrado"
        return 1
    fi
    
    echo "Leyendo archivos AWS desde: $aws_dir"
    
    local credentials_file="$aws_dir/credentials"
    local config_file="$aws_dir/config"
    
    # Leer credentials
    if [[ -f "$credentials_file" ]]; then
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
    fi
    
    # Leer config para región
    if [[ -f "$config_file" ]]; then
        local config_profile="profile $AWS_PROFILE"
        [[ "$AWS_PROFILE" == "default" ]] && config_profile="default"
        
        AWS_REGION=$(awk -F'=' -v profile="$config_profile" '
            $0 ~ "\\[" profile "\\]" { found=1; next }
            found && /^\[/ { found=0 }
            found && /region/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }
        ' "$config_file")
    fi
}

# Función para leer variables de entorno
read_env_variables() {
    echo "Usando variables de entorno como fallback..."
    [[ -z "$AWS_ACCESS_KEY_ID" ]] && AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
    [[ -z "$AWS_SECRET_ACCESS_KEY" ]] && AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
    [[ -z "$AWS_SESSION_TOKEN" ]] && AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"
    [[ -z "$AWS_REGION" ]] && AWS_REGION="${AWS_REGION:-$AWS_DEFAULT_REGION}"
}

# Función para generar session token
generate_session_token() {
    if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
        return 1
    fi
    
    if ! command -v aws >/dev/null 2>&1; then
        echo "AWS CLI no disponible, usando credenciales directas"
        return 1
    fi
    
    echo "Generando session token temporal..."
    echo "AWS_REGION: $AWS_REGION"

    # Exportar las variables temporalmente para el comando AWS
    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
    export AWS_REGION="$AWS_REGION"
    
    # Limpiar cualquier session token previo para evitar conflictos
    unset AWS_SESSION_TOKEN
    
    local sts_output
    local aws_exit_code
    
    # Ejecutar el comando y capturar tanto la salida como el código de salida
    sts_output=$(aws sts get-session-token \
                 --duration-seconds 3600 \
                 --output json 2>&1)
    aws_exit_code=$?

    if [[ $aws_exit_code -eq 0 ]]; then
        # Usar jq si está disponible para un parsing más confiable
        if command -v jq >/dev/null 2>&1; then
            AWS_ACCESS_KEY_ID=$(echo "$sts_output" | jq -r '.Credentials.AccessKeyId')
            AWS_SECRET_ACCESS_KEY=$(echo "$sts_output" | jq -r '.Credentials.SecretAccessKey')
            AWS_SESSION_TOKEN=$(echo "$sts_output" | jq -r '.Credentials.SessionToken')
        else
            # Fallback usando grep (método original pero mejorado)
            AWS_ACCESS_KEY_ID=$(echo "$sts_output" | grep -o '"AccessKeyId"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            AWS_SECRET_ACCESS_KEY=$(echo "$sts_output" | grep -o '"SecretAccessKey"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            AWS_SESSION_TOKEN=$(echo "$sts_output" | grep -o '"SessionToken"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        fi
        
        # Verificar que se extrajeron los valores correctamente
        if [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" && -n "$AWS_SESSION_TOKEN" ]]; then
            echo "Session token generado exitosamente"
            return 0
        else
            echo "Error: No se pudieron extraer las credenciales del JSON"
            echo "Respuesta de AWS STS: $sts_output"
            return 1
        fi
    else
        echo "Error al ejecutar aws sts get-session-token"
        echo "Código de salida: $aws_exit_code"
        echo "Salida del comando: $sts_output"
        return 1
    fi
}

# Detectar OS y leer archivos
case "$(uname -s)" in
    "Linux"|"Darwin")
        read_aws_files "$HOME/.aws"
        ;;
    "CYGWIN"*|"MINGW"*|"MSYS"*)
        if [[ -d "$HOME/.aws" ]]; then
            read_aws_files "$HOME/.aws"
        elif [[ -n "${USERPROFILE:-}" && -d "$USERPROFILE/.aws" ]]; then
            read_aws_files "$USERPROFILE/.aws"
        fi
        ;;
esac

# Completar con variables de entorno SOLO si no se encontraron en archivos
if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
    read_env_variables
fi

# Validar credenciales mínimas
if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
    echo "Error: Credenciales AWS no encontradas"
    echo "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:-(vacío)}"
    echo "AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:-(vacío)}"
    exit 1
fi

# Generar session token si no existe (FATAL si falla)
if [[ -z "$AWS_SESSION_TOKEN" ]]; then
    if ! generate_session_token; then
        echo "No se pudo generar session token. Abortando."
        exit 1
    fi
fi

# Configurar región por defecto
[[ -z "$AWS_REGION" ]] && AWS_REGION="us-east-1"

# Generar archivo de variables para Docker
echo "Generando archivo de variables: $OUTPUT_FILE"
cat > "$OUTPUT_FILE" << EOF
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
AWS_REGION=$AWS_REGION
EOF

echo "Credenciales configuradas - Region: $AWS_REGION"