# Compila la console personalizzata e la inserisce nell'immagine del backend.
# Il risultato è un'unica immagine autosufficiente: nessun file da tenere
# sull'host, nessun bind mount da ricordarsi quando si sposta il server.

FROM node:22-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM lejianwen/rustdesk-api:latest
# Il backend serve la console da /app/resources/admin (Gin.ResourcesPath).
COPY --from=build /src/dist /app/resources/admin
