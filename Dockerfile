ARG RUBY_VERSION=3.2.2

FROM ruby:$RUBY_VERSION-slim as base

ARG BUILD_ENV=development
ARG RUBY_ENV=development
ARG NODE_ENV=development
ARG ASSET_HOST=http://localhost
# Set environment varaibles required in the initializers in order to precompile the assets.
# Because it initializes the app, so all variables need to exist in the build stage.
ARG MAILER_DEFAULT_HOST=http://localhost
ARG MAILER_DEFAULT_PORT=3000
ARG SECRET_KEY_BASE=secret_key_base
ARG MAILGUN_SMTP_PORT=mailgun_smtp_port
ARG MAILGUN_SMTP_SERVER=mailgun_smtp_server
ARG MAILGUN_SMTP_LOGIN=mailgun_smtp_login
ARG MAILGUN_SMTP_PASSWORD=mailgun_smtp_password
ARG APP_DOMAIN=app_domain
ARG BASIC_AUTHENTICATION_USERNAME
ARG BASIC_AUTHENTICATION_PASSWORD

# Define all the envs here
ENV BUILD_ENV=$BUILD_ENV \
    RACK_ENV=$RUBY_ENV \
    RAILS_ENV=$RUBY_ENV \
    NODE_ENV=$NODE_ENV \
    ASSET_HOST=$ASSET_HOST \
    APP_HOME=/multi-stages \
    PORT=80 \
    BUNDLE_JOBS=4 \
    BUNDLE_PATH="/usr/local/bundle" \
    NODE_VERSION=18 \
    LANG="en_US.UTF-8" \
    LC_ALL="en_US.UTF-8" \
    LANGUAGE="en_US:en"

# Throw-away build stage to reduce size of final image
FROM base as builder

WORKDIR /tmp

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends apt-transport-https curl gnupg net-tools && \
    apt-get install -y --no-install-recommends build-essential libpq-dev shared-mime-info && \
    apt-get install -y --no-install-recommends rsync locales chrpath pkg-config libfreetype6 libfontconfig1 git cmake wget unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy all denpendencies from app and engines into tmp/docker to install
FROM builder AS bundler

WORKDIR $APP_HOME

# Skip installing gem documentation
RUN mkdir -p /usr/local/etc \
    && { \
    echo '---'; \
    echo ':update_sources: true'; \
    echo ':benchmark: false'; \
    echo ':backtrace: true'; \
    echo ':verbose: true'; \
    echo 'gem: --no-ri --no-rdoc'; \
    echo 'install: --no-document'; \
    echo 'update: --no-document'; \
    } >> /usr/local/etc/gemrc

COPY tmp/docker ./

# Install Ruby gems
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile


# Compile assets
FROM builder AS assets

# Add Yarn repository
# Add the PPA (personal package archive) maintained by NodeSource
# This will have more up-to-date versions of Node.js than the official Debian repositories
ADD https://dl.yarnpkg.com/debian/pubkey.gpg /tmp/yarn-pubkey.gpg
RUN set -uex; \
    apt-get update -qq; \
    apt-get install -y ca-certificates curl gnupg; \
    mkdir -p /etc/apt/keyrings; \
    apt-key add /tmp/yarn-pubkey.gpg && rm /tmp/yarn-pubkey.gpg && \
    echo "deb http://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_VERSION.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends nodejs yarn && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY package.json yarn.lock .yarnrc ./
RUN yarn install

COPY --from=bundler $BUNDLE_PATH $BUNDLE_PATH
COPY . ./

RUN bundle exec rails i18n:js:export
RUN bundle exec rails assets:precompile
# RUN yarn run build:docs

# Final image
FROM builder AS app

WORKDIR $APP_HOME

COPY --from=bundler /usr/local/bundle /usr/local/bundle
COPY --from=assets /tmp/public public

COPY . ./

# Remove tmp/docker in the final image
RUN rm -rf tmp/docker

EXPOSE $PORT

CMD ["./bin/start.sh"]
