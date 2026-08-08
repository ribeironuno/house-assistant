FROM node:20

WORKDIR /app

RUN apt-get update && apt-get install -y \
    chromium \
    chromium-sandbox \
    && rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

COPY package*.json ./
COPY patches ./patches
RUN npm install

COPY . .

EXPOSE 3000

CMD ["npm", "start"]