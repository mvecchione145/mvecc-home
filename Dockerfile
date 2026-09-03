# ---- build ----------------------------------------------------------------
FROM node:22-alpine AS build
WORKDIR /app

# Install deps against the lockfile first so this layer caches.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

# ---- dev ------------------------------------------------------------------
# Used only by docker-compose's `dev` service. Sources are bind-mounted over
# /app at runtime, so this stage exists mainly to hold node_modules.
FROM node:22-alpine AS dev
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]

# ---- serve ----------------------------------------------------------------
FROM nginx:1.27-alpine AS serve

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
