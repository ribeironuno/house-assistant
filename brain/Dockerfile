FROM elixir:1.18-alpine AS builder

RUN apk add --no-cache build-base git

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY config config
COPY lib lib
COPY priv priv

RUN mix compile

FROM elixir:1.18-alpine

RUN apk add --no-cache libstdc++ ncurses-libs openssl postgresql-client

RUN addgroup -g 1000 -S app && adduser -u 1000 -S app -G app

WORKDIR /app

COPY --from=builder /app .

RUN chown -R app:app /app

USER app

ENV MIX_HOME=/app/.mix

RUN mix local.hex --force && mix local.rebar --force

EXPOSE 4000

ENV PORT=4000
ENV PHX_SERVER=true

CMD ["sh", "-c", "mix ecto.migrate && mix phx.server"]
