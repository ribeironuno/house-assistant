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

EXPOSE 4000

ENV PORT=4000
ENV PHX_SERVER=true

CMD ["sh", "-c", "mix ecto.migrate && mix phx.server"]
