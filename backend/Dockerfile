FROM node:24-alpine AS build
WORKDIR /app
COPY package*.json ./
COPY backend/package.json backend/package.json
RUN npm ci
COPY backend/src backend/src
COPY backend/tsconfig.json backend/tsconfig.json
RUN npm run build -w backend && npm prune --omit=dev

FROM node:24-alpine
ENV NODE_ENV=production HOST=0.0.0.0 PORT=4318
WORKDIR /app
COPY --from=build /app/node_modules node_modules
COPY --from=build /app/backend/package.json package.json
COPY --from=build /app/backend/dist dist
USER node
EXPOSE 4318
CMD ["node", "dist/server.js"]
