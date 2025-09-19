# Multi-stage build: build React then run with Node/Express
FROM node:18-alpine as build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM node:18-alpine
WORKDIR /app
ENV NODE_ENV=production

# Copy build output from first stage
COPY --from=build /app/build ./build

# Production deps only (react build already compiled)
COPY package*.json ./
RUN npm install --only=production

# Copy only server source (no need for entire src except server.js)
COPY src/server.js ./src/server.js

# Expose frontend port
EXPOSE 3000

ENV PORT=3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["npm", "run", "serve"]