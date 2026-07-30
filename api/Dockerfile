# syntax=docker/dockerfile:1
#
# 本番用イメージ。ビルドコンテキストは api/ ディレクトリ
# （Coolify では Base Directory に /api を指定する。docs/DEPLOY.md 参照）。

ARG RUBY_VERSION=3.3.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    RAILS_ENV="production"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# ---- ビルド段: ネイティブ拡張のビルドに必要なものはここだけに置く ----
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY . .

RUN bundle exec bootsnap precompile app/ lib/

# ---- 実行段 ----
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# GitHub Actions が採番したバージョンを /health で返せるようにする
ARG APP_VERSION=unknown
ENV APP_VERSION=$APP_VERSION

# root では動かさない
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3001
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3001"]
