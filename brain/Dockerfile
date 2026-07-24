FROM elixir:1.18-alpine

RUN apk add --no-cache build-base git

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get && mix deps.compile

COPY config ./config
COPY lib ./lib
COPY priv ./priv

EXPOSE 4000

ENV PORT=4000
ENV MIX_ENV=dev
ENV PHX_SERVER=true

CMD ["mix", "phx.server"]
