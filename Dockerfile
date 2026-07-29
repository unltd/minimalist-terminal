# Dev image for building and testing the plugin in a consistent Linux environment
FROM node:22-alpine

RUN addgroup -S dev && adduser -S dev -G dev

RUN apk add --no-cache \
    bash \
    python3 \
    py3-pip \
    gauge

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

USER dev

CMD ["bash"]
