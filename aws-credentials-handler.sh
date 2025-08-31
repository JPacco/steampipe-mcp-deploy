#!/bin/bash

set -e

AWS_PROFILE="${AWS_PROFILE:-default}"
OUTPUT_FILE="${1:-/tmp/aws_env_vars}"

# Variables para credenciales
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_SESSION_TOKEN=""
AWS_REGION=""

# Función para leer archivos AWS
read_aws_files() {
    local aws_dir="$1"
    
    if [[ ! -d "$aws_dir" ]]; then
        return 1
    fi
    
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
        return 1
    fi
    
    local sts_output
    sts_output=$(AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
                 AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
                 aws sts get-session-token \
                 --duration-seconds 3600 \
                 --output json 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        AWS_ACCESS_KEY_ID=$(echo "$sts_output" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)
        AWS_SECRET_ACCESS_KEY=$(echo "$sts_output" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)
        AWS_SESSION_TOKEN=$(echo "$sts_output" | grep -o '"SessionToken": "[^"]*"' | cut -d'"' -f4)
        return 0
    else
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

# Completar con variables de entorno
read_env_variables

# Validar credenciales mínimas
if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
    echo "Error: Credenciales AWS no encontradas"
    exit 1
fi

# Generar session token si no existe
if [[ -z "$AWS_SESSION_TOKEN" ]]; then
    generate_session_token || true
fi

# Configurar región por defecto
[[ -z "$AWS_REGION" ]] && AWS_REGION="us-east-1"

# Generar archivo de variables para Docker
cat > "$OUTPUT_FILE" << EOF
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
AWS_REGION=$AWS_REGION
EOF