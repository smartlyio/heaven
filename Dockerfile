FROM ruby:2.3-jessie

ENV NODE_VERSION node_8.x
ENV DISTRO jessie

RUN apt-get update --quiet=2 \
  && apt-get install --assume-yes --no-install-recommends apt-transport-https \
  && echo "deb http://ppa.launchpad.net/ansible/ansible/ubuntu trusty main" > /etc/apt/sources.list.d/ansible.list \
  && echo "deb-src http://deb.debian.org/debian unstable main" > /etc/apt/sources.list.d/unstable.list \
  && echo "deb https://deb.nodesource.com/$NODE_VERSION $DISTRO main" > /etc/apt/sources.list.d/nodesource.list \
  && echo "deb-src https://deb.nodesource.com/$NODE_VERSION $DISTRO main" >> /etc/apt/sources.list.d/nodesource.list \
  && echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list \
  && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367 \
  && curl --silent https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - \
  && curl --silent --show-error https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
  && apt-get update --quiet=2 \
  && apt-get install --assume-yes --no-install-recommends ansible=2.3.2.0-1ppa~trusty nodejs=8.4.0-1nodesource1~jessie1 yarn=0.27.5-1 build-essential \
  && apt-get build-dep --assume-yes --no-install-recommends git-crypt=0.5.0-2 \
  && apt-get -b source git-crypt \
  && dpkg -i git-crypt_0.5.0-2_amd64.deb \
  && rm -rf git-crypt* \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/bin

RUN wget https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh \
  && chmod a+x wait-for-it.sh

RUN mkdir -p /root/.ssh

ENV WORK_DIR /usr/lib/heaven
ENV BUNDLE_PATH /bundle

WORKDIR $WORK_DIR

COPY Gemfile Gemfile.lock ./
RUN gem update --system \
  && gem install bundler --version 1.15.1 \
  && bundle install --full-index \
  && bundle clean --force

COPY ./bin/docker-entrypoint.sh /docker-entrypoint.sh
COPY ./id_rsa /root/.ssh/
COPY ./id_rsa.pub /root/.ssh/

COPY . ./

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["unicorn", "-p", "80", "-c", "config/unicorn.rb"]
