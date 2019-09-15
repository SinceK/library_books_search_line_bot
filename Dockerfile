FROM ruby:2.5.3
ENV LANG C.UTF-8
RUN apt-get update -qq && \
    apt-get install -y build-essential \
                       libpq-dev \
                       nodejs
RUN gem install bundler
RUN mkdir /library_books_search_bot
WORKDIR /library_books_search_bot
COPY Gemfile /library_books_search_bot/Gemfile
COPY Gemfile.lock /library_books_search_bot/Gemfile.lock
RUN bundle install
COPY . /library_books_search_bot
