FROM oven/bun:1.0.11 AS build
RUN apt-get update && apt-get install -y python3 build-essential && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY src/package*.json ./
COPY src/bun.lockb ./bun.lockb
RUN bun install
COPY src .
COPY .env.build .env.local
RUN if [ ! -s .env.local ]; then echo "Missing .env.build. Run bin/stoatctl deploy admin to generate it." && exit 1; fi
RUN bun run build

FROM oven/bun:1.0.11
WORKDIR /app
COPY --from=build /app .
ENV NODE_ENV=production
EXPOSE 3000
CMD ["bun", "run", "start"]
