#!/usr/bin/env bash
set -e
set -x

bundle check || bundle install
bundle exec rake db:migrate
bundle exec "$@"
