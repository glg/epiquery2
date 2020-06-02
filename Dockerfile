FROM 868468680417.dkr.ecr.us-east-1.amazonaws.com/ops.glgresearch.com/stardock-base

SHELL ["/bin/bash", "-c"]
# adding our node_modules bin to the path so we can reference installed packages
# without installing them globally
ENV PATH="/var/app/node_modules/.bin:${PATH}"
RUN mkdir -p /var/app
RUN apt-get update && \
    apt-get install curl git && \
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash && \
    source /root/.nvm/nvm.sh && \
    nvm install v12.16.3
    

WORKDIR /var/app
COPY package.json /var/app
RUN source /root/.nvm/nvm.sh && \
    npm install
COPY . /var/app

CMD ["/bin/bash", "-c", "source /root/.nvm/nvm.sh && /var/app/epistream.coffee"]
