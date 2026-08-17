FROM node:20-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    fonts-ipafont-gothic \
    fonts-wqy-zenhei \
    fonts-thai-tlwg \
    fonts-khmeros \
    fonts-freefont-ttf \
    && rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

WORKDIR /app

COPY package.json package-lock.json ./
COPY patches ./patches

RUN npm ci && npm cache clean --force

COPY . .

RUN groupadd -r nodeuser && useradd -r -g nodeuser nodeuser
RUN chown -R nodeuser:nodeuser /app
USER nodeuser

EXPOSE 3000

# Remove stale Chromium profile locks left behind by previous container runs.
# whatsapp-web.js stores sessions in /app/.wwebjs_auth/{clientId}/ (mounted as a volume).
CMD ["sh", "-c", "rm -f /app/.wwebjs_auth/*/SingletonLock /app/.wwebjs_auth/*/SingletonSocket /app/.wwebjs_auth/*/SingletonCookie && npm start"]
