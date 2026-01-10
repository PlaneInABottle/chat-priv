# pre-build stage
FROM node:23.7.0-alpine AS node
FROM ruby:3.4.4-alpine3.21 AS pre-builder

ARG NODE_VERSION="24.13.0"
ARG PNPM_VERSION="10.2.0"
ENV NODE_VERSION=${NODE_VERSION}
ENV PNPM_VERSION=${PNPM_VERSION}

# ARG default to production settings
# For development docker-compose file overrides ARGS
ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT ${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=4.0.3

ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES ${RAILS_SERVE_STATIC_FILES}

ARG RAILS_ENV=production
ENV RAILS_ENV ${RAILS_ENV}

ARG NODE_OPTIONS="--max-old-space-size=3072 --openssl-legacy-provider"
ENV NODE_OPTIONS ${NODE_OPTIONS}

# Memory optimization for Ruby/Bundler during build
ENV RUBY_GC_HEAP_GROWTH_FACTOR=1.1
ENV RUBY_GC_MALLOC_LIMIT=16000000
ENV MALLOC_ARENA_MAX=2

ENV BUNDLE_PATH="/gems"

RUN apk add --no-cache \
  openssl \
  openssl-dev \
  tar \
  build-base \
  tzdata \
  postgresql-dev \
  postgresql-client \
  git \
  curl \
  xz \
  musl-dev \
  linux-headers \
  ruby-full \
  ruby-dev \
  vips \
  && mkdir -p /var/app \
  && gem install bundler -v 4.0.3 --no-document

COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

RUN npm install -g pnpm@${PNPM_VERSION}

RUN echo 'export PNPM_HOME="/root/.local/share/pnpm"' >> /root/.shrc \
  && echo 'export PATH="$PNPM_HOME:$PATH"' >> /root/.shrc \
  && export PNPM_HOME="/root/.local/share/pnpm" \
  && export PATH="$PNPM_HOME:$PATH" \
  && pnpm --version

# Persist the environment variables in Docker
ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local force_ruby_platform true

# Do not install development or test gems in production
# Using -j 2 to reduce memory usage during parallel gem compilation
RUN if [ "$RAILS_ENV" = "production" ]; then \
  bundle config set without 'development test'; bundle install -j 2 -r 3; \
  else bundle install -j 2 -r 3; \
  fi

# Clean gem cache and build artifacts immediately to free memory before pnpm
RUN rm -rf /gems/ruby/*/cache/*.gem \
  && find /gems \( -name "*.c" -o -name "*.o" \) -delete 2>/dev/null || true

COPY package.json pnpm-lock.yaml ./
# Disable Husky git hooks in Docker builds (no .git directory in final image)
ENV HUSKY=0
RUN pnpm i --frozen-lockfile

COPY . /app

# creating a log directory so that image wont fail when RAILS_LOG_TO_STDOUT is false
# https://github.com/chatwoot/chatwoot/issues/701
RUN mkdir -p /app/log

# generate production assets if production environment
# Memory optimizations: Disable Spring, reduce GC pressure, constrain memory
RUN if [ "$RAILS_ENV" = "production" ]; then \
  DISABLE_SPRING=1 \
  MALLOC_ARENA_MAX=2 \
  RUBY_GC_HEAP_GROWTH_FACTOR=1.1 \
  SECRET_KEY_BASE=precompile_placeholder \
  RAILS_LOG_TO_STDOUT=enabled \
  bundle exec rake assets:precompile \
  && rm -rf spec node_modules tmp/cache .pnpm-store; \
  fi

# Remove unnecessary files and clean up
RUN rm -rf /gems/ruby/*/cache/*.gem \
  && find /gems \( -name "*.c" -o -name "*.o" \) -delete 2>/dev/null || true \
  && rm -rf .git .gitignore tmp/cache

RUN mkdir -p /app/tmp/cache /app/tmp/pids /app/tmp/sockets

# final build stage
FROM ruby:3.4.4-alpine3.21

ARG NODE_VERSION="24.13.0"
ARG PNPM_VERSION="10.2.0"
ARG GIT_SHA="unknown"
ENV NODE_VERSION=${NODE_VERSION}
ENV PNPM_VERSION=${PNPM_VERSION}

ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT ${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=4.0.3

ARG EXECJS_RUNTIME="Disabled"
ENV EXECJS_RUNTIME ${EXECJS_RUNTIME}

ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES ${RAILS_SERVE_STATIC_FILES}

ARG BUNDLE_FORCE_RUBY_PLATFORM=1
ENV BUNDLE_FORCE_RUBY_PLATFORM ${BUNDLE_FORCE_RUBY_PLATFORM}

ARG RAILS_ENV=production
ENV RAILS_ENV ${RAILS_ENV}
ENV BUNDLE_PATH="/gems"

RUN apk add --no-cache \
  openssl \
  tzdata \
  postgresql-client \
  imagemagick \
  vips \
  libstdc++ \
  && gem install bundler -v 4.0.3 --no-document

COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN if [ "$RAILS_ENV" != "production" ]; then \
  apk add --no-cache curl git \
  && ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
  && npm install -g pnpm@${PNPM_VERSION} \
  && pnpm --version; \
  fi

COPY --from=pre-builder /gems/ /gems/
COPY --from=pre-builder /app /app

WORKDIR /app

RUN adduser -D -u 1000 chatwoot \
  && echo "${GIT_SHA}" > /app/.git_sha \
  && chown -R chatwoot:chatwoot /app /gems

USER chatwoot

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]

EXPOSE 3000
