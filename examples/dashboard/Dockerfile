FROM hexpm/elixir:1.15.6-erlang-26.0.2-debian-bookworm-20240701-slim AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /src
# The framework (path dep) …
COPY mix.exs mix.lock ./
COPY lib lib
COPY priv priv
# … and the showcase app.
COPY examples/dashboard examples/dashboard

WORKDIR /src/examples/dashboard
RUN mix deps.get --only prod && mix compile && mix release

FROM debian:bookworm-20240701-slim AS runner

RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 HOME=/app
WORKDIR /app
COPY --from=builder /src/examples/dashboard/_build/prod/rel/virtuoso_dashboard ./

CMD ["/app/bin/virtuoso_dashboard", "start"]
