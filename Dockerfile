FROM node:20-alpine

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev --no-audit --no-fund \
  && node -e "require('dotenv'); require('express'); require('mqtt'); require('pg')"
COPY . .

EXPOSE 3000 4000
CMD ["npm", "run", "start:backend"]
