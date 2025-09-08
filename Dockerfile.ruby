# Dockerfile.ruby - image for the Ruby orchestrator
FROM ruby:3.2-slim

# Install essentials
RUN apt-get update \
  && apt-get install -y build-essential git curl libpq-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Gemfile first to leverage Docker cache
COPY Gemfile Gemfile.lock* /app/

# Install bundler and gems
RUN gem install bundler -v "$(grep bundler Gemfile || echo '')" --no-document || true
RUN bundle install --jobs 4 --retry 3

# Copy app files
COPY . /app

# Expose nothing (Ruby orchestrator communicates with python service internally)
ENV DATA_PATH /app/stores_sales_forecasting.pandas.csv
ENV OUT_DIR /app/output

# Default command: a shell to interact
CMD ["bash"]
