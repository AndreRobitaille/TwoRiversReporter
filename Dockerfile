# syntax=docker/dockerfile:1@sha256:34b128e419449565adc5ed7f487a6f503a73f1077012cfed86354c731338c44f
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t two_rivers_reporter .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name two_rivers_reporter two_rivers_reporter

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.6
ARG RUBY_IMAGE_DIGEST=sha256:75a93fb37a4d2b1bb72939f5d67c270cf7e531ae9c9144d3c5173c16c8d6bbb8
FROM docker.io/library/ruby:$RUBY_VERSION-slim@$RUBY_IMAGE_DIGEST AS base

ARG DENO_VERSION=2.9.6
ARG DENO_SHA256=394f07f4da2bebe6ce6f1e7ce0fa16429b29b08c35e3fac3fe25972676dff4b2
ARG YT_DLP_VERSION=2026.08.19
ARG YT_DLP_SHA256=58162f9bfdc27458ea47bfcb311cf47028f17d8154a8bf7d689861d46399230a

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips nodejs postgresql-client poppler-utils tesseract-ocr unzip && \
    curl --fail --show-error --location "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-x86_64-unknown-linux-gnu.zip" -o /tmp/deno.zip && \
    echo "${DENO_SHA256}  /tmp/deno.zip" | sha256sum --check --strict && \
    unzip -q /tmp/deno.zip -d /usr/local/bin && \
    rm /tmp/deno.zip && \
    curl --fail --show-error --location "https://github.com/yt-dlp/yt-dlp/releases/download/${YT_DLP_VERSION}/yt-dlp_linux" -o /usr/local/bin/yt-dlp && \
    echo "${YT_DLP_SHA256}  /usr/local/bin/yt-dlp" | sha256sum --check --strict && \
    chmod +x /usr/local/bin/yt-dlp && \
    yt-dlp --version && \
    deno --version && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock vendor ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompile assets for production without requiring secret RAILS_MASTER_KEY.
# Propshaft preserves restrictive modes on copied binary assets. Kamal's asset
# bridge later owns those files as root, so they must remain readable by the
# unprivileged Rails process that serves them.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    chmod -R a+rX public/assets




# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
