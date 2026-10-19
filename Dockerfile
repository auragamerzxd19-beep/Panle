# AuraPanel - Railway / Docker deployment
FROM node:20-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssl python3 build-essential ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=production APP_NAME=AuraPanel INSTALL_DIR_RAILWAY=/app RAILWAY_ENVIRONMENT=docker
COPY install.sh /tmp/install.sh
RUN bash /tmp/install.sh
# Railway injects $PORT; the panel reads PORT from env
CMD ["sh", "-c", "cd /app && npm start"]
