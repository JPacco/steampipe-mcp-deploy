#!/bin/bash

# start.sh - Script simple para ejecutar Steampipe con docker-compose

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_ENV_FILE="$SCRIPT_DIR/.aws_env"

echo "🔐 Preparando credenciales AWS..."
bash "$SCRIPT_DIR/aws-credentials-handler.sh" "$AWS_ENV_FILE"

echo "🚀 Iniciando Steampipe con docker-compose..."
docker-compose --env-file "$AWS_ENV_FILE" up -d

echo "✅ Steampipe iniciado"
echo "💡 Para acceder: docker-compose exec steampipe bash"
echo "💡 Para detener: docker-compose down"