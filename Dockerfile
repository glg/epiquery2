FROM node:5.5.0

RUN printf "deb http://archive.debian.org/debian/ jessie main\ndeb-src http://archive.debian.org/debian/ jessie main\ndeb http://security.debian.org jessie/updates main\ndeb-src http://security.debian.org jessie/updates main" > /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y \ 
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        make \
        jq \
        bc \
        python-dev \
        curl \
        gnupg2 \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - \
    && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    && apt-get update \
    && apt-get install -y  docker-ce \
    && curl -O https://bootstrap.pypa.io/get-pip.py \
    && python get-pip.py \
    && pip install awscli \
    && npm install -g igroff/difftest-runner coffee-script

ADD . /var/app
WORKDIR /var/app
RUN npm install
RUN mkdir /var/config


#ENTRYPOINT ["/bin/bash"]
#CMD ["./epistream-docker-secrets-entrypoint.sh"]
CMD ["./node_modules/.bin/supervisor", "-e", ".litcoffee|.coffee|.js",  "./epistream.coffee"]
