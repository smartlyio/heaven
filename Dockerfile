FROM ubuntu:bionic

RUN apt-get update --quiet=2 \
  && apt-get upgrade --assume-yes \
  && apt-get install --assume-yes --no-install-recommends gnupg wget ca-certificates git-crypt ruby bundler \
  build-essential ruby-dev zlib1g-dev libxml2-dev libxslt-dev libpq-dev libsqlite3-dev openssh-client python-git python-requests

RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367 1646B01B86E50310 \
  && echo "deb http://ppa.launchpad.net/ansible/ansible-2.8/ubuntu bionic main" > /etc/apt/sources.list.d/ansible-2.8.list \
  && echo "deb http://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list \
  && apt-get update --quiet=2 \
  && apt-get install --assume-yes --no-install-recommends ansible=2.8.* curl nodejs=8.* yarn \
  && apt-get autoremove --assume-yes \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/bin

RUN wget https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh \
  && echo '2ea7475e07674e4f6c1093b4ad6b0d8cbbc6f9c65c73902fb70861aa66a6fbc0  wait-for-it.sh' | sha256sum -c - \
  && chmod a+x wait-for-it.sh

RUN mkdir -p /root/.ssh
RUN mkdir /bundle

ENV WORK_DIR /usr/lib/heaven

WORKDIR $WORK_DIR

COPY ./bin/docker-entrypoint.sh /docker-entrypoint.sh
COPY . ./
RUN bundle install

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["unicorn", "-p", "80", "-c", "config/unicorn.rb"]
