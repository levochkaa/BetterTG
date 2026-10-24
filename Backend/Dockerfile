FROM rust:1.99-slim-trixie AS build

WORKDIR /app
COPY Cargo.toml Cargo.lock rustfmt.toml ./
# Compile the dependencies once, against placeholder sources, so source edits rebuild only the crate.
RUN mkdir -p src/bin \
    && echo 'fn main() {}' > src/main.rs \
    && touch src/lib.rs \
    && echo 'fn main() {}' > src/bin/smoke-relay.rs \
    && echo 'fn main() {}' > src/bin/update-push-catalog.rs \
    && cargo build --release --locked \
    && rm -rf src
COPY src ./src
RUN touch src/main.rs src/lib.rs && cargo build --release --locked --bin bettertg-backend

FROM debian:trixie-slim AS runtime

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 1000 --user-group --no-create-home --shell /usr/sbin/nologin bettertg
COPY --from=build /app/target/release/bettertg-backend /usr/local/bin/bettertg-backend
ENV NODE_ENV=production
USER bettertg
CMD ["bettertg-backend", "api"]
