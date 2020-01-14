FROM node:5.5.0-alpine

RUN npm install -g igroff/difftest-runner coffee-script

ADD ./package.json /var/app/package.json
WORKDIR /var/app
RUN npm install
ADD . /var/app
RUN mkdir /var/config

RUN make build

#ENTRYPOINT ["/bin/bash"]
#CMD ["./epistream-docker-secrets-entrypoint.sh"]
CMD ["./epistream.coffee"]