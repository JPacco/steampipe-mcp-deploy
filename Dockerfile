FROM amazonlinux:2023 AS builder

# Instalar herramientas y crear usuario en una sola capa
RUN dnf install -y jq tar gzip shadow-utils && \
    dnf clean all && \
    useradd -m -s /bin/bash steampipe

# Obtener la última versión dinámicamente
RUN LATEST_VERSION=$(curl -s https://api.github.com/repos/turbot/steampipe/releases/latest | jq -r '.tag_name') && \
    echo "Downloading Steampipe version: $LATEST_VERSION" && \
    curl -L "https://github.com/turbot/steampipe/releases/download/${LATEST_VERSION}/steampipe_linux_amd64.tar.gz" \
      -o /tmp/steampipe.tar.gz && \
    tar -xzf /tmp/steampipe.tar.gz -C /usr/local/bin steampipe && \
    rm -rf /tmp/steampipe.tar.gz && \
    chmod +x /usr/local/bin/steampipe

# Cambiar a usuario steampipe ANTES de instalar plugins
USER steampipe
WORKDIR /home/steampipe

# Desactivar checks para acelerar build
ENV STEAMPIPE_UPDATE_CHECK=false

# Instalar plugin como usuario steampipe
RUN steampipe plugin install aws && \
    steampipe plugin list > /dev/null

### =========================
### Stage 2: runtime
### =========================
FROM amazonlinux:2023

# Instalar AWS CLI y crear usuario en una SOLA capa
RUN dnf install -y shadow-utils util-linux unzip && \
    useradd -m -s /bin/bash steampipe && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip -q awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip && \
    dnf remove -y shadow-utils unzip && \
    dnf clean all && \
    rm -rf /var/cache/dnf /var/lib/rpm/__db*

# Copiar binario y cache precargada
COPY --from=builder /usr/local/bin/steampipe /usr/local/bin/steampipe
COPY --from=builder --chown=steampipe:steampipe /home/steampipe/.steampipe /home/steampipe/.steampipe

# Configuración final
ENV STEAMPIPE_UPDATE_CHECK=false
USER steampipe
WORKDIR /home/steampipe

CMD ["sleep", "infinity"]