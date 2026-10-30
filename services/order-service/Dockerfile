FROM node:20-alpine AS builder

WORKDIR /build
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

FROM node:20-alpine

WORKDIR /app
RUN addgroup -g 10001 appgroup && adduser -u 10001 -G appgroup -s /sbin/nologin -D appuser

COPY --from=builder /build/node_modules ./node_modules
COPY package.json server.js ./

RUN chown -R appuser:appgroup /app
USER 10001:10001

EXPOSE 8082
CMD ["node", "server.js"]
