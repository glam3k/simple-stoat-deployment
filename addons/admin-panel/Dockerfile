FROM oven/bun:1.0.11 AS build
RUN apt-get update && apt-get install -y python3 build-essential libssl-dev curl \
    && curl -fsSL http://deb.debian.org/debian/pool/main/o/openssl/libssl3_3.0.11-1~deb12u2_amd64.deb -o /tmp/libssl3.deb \
    && dpkg -i /tmp/libssl3.deb \
    && rm /tmp/libssl3.deb \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY src/package*.json ./
COPY src/bun.lockb ./bun.lockb
RUN bun install
COPY src .
COPY .env.build .env.local
RUN if [ ! -s .env.local ]; then echo "Missing .env.build. Run bin/stoatctl deploy admin to generate it." && exit 1; fi
RUN bun run build

FROM oven/bun:1.0.11
RUN apt-get update && apt-get install -y libssl-dev curl \
    && curl -fsSL http://deb.debian.org/debian/pool/main/o/openssl/libssl3_3.0.11-1~deb12u2_amd64.deb -o /tmp/libssl3.deb \
    && dpkg -i /tmp/libssl3.deb \
    && rm /tmp/libssl3.deb \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app .
ENV NODE_ENV=production
EXPOSE 3000
CMD ["bun", "run", "start"]
