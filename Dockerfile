FROM ruby:3.2.2-slim

ARG BUILD_ENV=development
ARG RUBY_ENV=development
ARG APP_HOME=/multi_stages
ARG NODE_ENV=development
ARG ASSET_HOST=http://localhost

# Define all the envs here
ENV BUILD_ENV=$BUILD_ENV \
    RACK_ENV=$RUBY_ENV \
    RAILS_ENV=$RUBY_ENV \
    PORT=80 \
    BUNDLE_JOBS=4 \
    BUNDLE_PATH="/bundle" \
    ASSET_HOST=$ASSET_HOST \
    NODE_ENV=$NODE_ENV \
    NODE_VERSION=18.19.0 \
    NODE_SOURCE_VERSION=18 \
    LANG="en_US.UTF-8" \
    LC_ALL="en_US.UTF-8" \
    LANGUAGE="en_US:en"

RUN set -uex; \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg && \
    apt-get install -y --no-install-recommends build-essential libpq-dev && \
    apt-get install -y --no-install-recommends rsync locales chrpath pkg-config libfreetype6 libfontconfig1 git cmake wget unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Add Yarn repository
# Add the PPA (personal package archive) maintained by NodeSource
# This will have more up-to-date versions of Node.js than the official Debian repositories
RUN mkdir -p /etc/apt/keyrings; \
    # Download Yarn source GPG key and add Yarn source to the source list
    curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/yarnsource.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/yarnsource.gpg] http://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list && \
    # Download nodesource GPG key and add nodesource to the source list
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_SOURCE_VERSION.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update -qq && \
    # Force installing the expected version: https://github.com/nodesource/distributions/wiki/How-to-select-the-Node.js-version-to-install
    apt-get install -y --no-install-recommends nodejs=${NODE_VERSION}-1nodesource1 yarn && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set up the Chrome PPA and install Chrome Headless
RUN if [ "$BUILD_ENV" = "test" ]; then \
      wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
      echo 'deb http://dl.google.com/linux/chrome/deb/ stable main' >> /etc/apt/sources.list.d/google-chrome.list && \
      apt-get update -qq && \
      apt-get install -y --no-install-recommends google-chrome-stable && \
      rm /etc/apt/sources.list.d/google-chrome.list && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* ; \
    fi

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

# Copy all denpendencies from app and engines into tmp/docker to install
COPY tmp/docker ./

# Install Ruby gems
RUN gem install bundler && \
    bundle config set jobs $BUNDLE_JOBS && \
    bundle config set path $BUNDLE_PATH && \
    if [ "$BUILD_ENV" = "production" ]; then \
      bundle config set deployment yes && \
      bundle config set without 'development test' ; \
    fi && \
    bundle install

# Install JS dependencies
COPY package.json yarn.lock ./
RUN yarn install --network-timeout 100000

# Copying the app files must be placed after the dependencies setup
# since the app files always change thus cannot be cached
COPY . ./

# Remove tmp/docker in the final image
RUN rm -rf tmp/docker

# Compile assets
RUN bin/docker-assets-precompile

EXPOSE $PORT

CMD ./bin/start.sh
