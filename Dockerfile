# ==============================================================
#	Notes: 
#	1) This is an experimental docker build for develoment / testing purposes.
#	2) Arguments set so far can be parsed into the build for USER, GROUP, SITE URL & BLACKFIRE
# ==============================================================
FROM wyveo/nginx-php-fpm:php74
MAINTAINER Tony Clemmey "tonyclemmey@gmail.com"

# ==============================================================
# 	Replacing the internal user/group IDs with known, good values 
# 	Host system first user with 1000:1000 after root 0:0 (SFTP Docker Volumes)
# 	https://jtreminio.com/blog/running-docker-containers-as-current-host-user/#ok-so-what-actually-works
# ==============================================================
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN userdel -f nginx && \
    if getent group nginx ; then groupdel nginx; fi && \
    groupadd -g ${GROUP_ID} nginx && \
    useradd -l -u ${USER_ID} -g nginx nginx && \
    install -d -m 0755 -o nginx -g nginx /home/nginx && \
    chown --changes --silent --no-dereference --recursive \
      --from=101:101 ${USER_ID}:${GROUP_ID} \
    /home/nginx \
    /root/.composer \
    /var/run/php \
    /var/lib/php/sessions \
    /usr/share/nginx

# ==============================================================
# 	Set the domain / server name to be used (used when creating mkcert SSL certs)
# 	($ docker build -t test-build:v1 --build-arg URL=example.com)
# 	https://blog.bitsrc.io/how-to-pass-environment-info-during-docker-builds-1f7c5566dd0e
# ==============================================================
ARG URL=mysite.test
ENV DOMAIN_URL $URL

# ==============================================================
# 	Set craft cms version
# ==============================================================
ENV CRAFT_VERSION=2.9 CRAFT_BUILD=2
ENV CRAFT_ZIP=Craft-$CRAFT_VERSION.$CRAFT_BUILD.zip

# ==============================================================
# 	Set nvm, node environment variables
# ==============================================================
RUN mkdir /root/.nvm
ENV NVM_VERSION v0.35.2
ENV NVM_DIR /root/.nvm
ENV NODE_VERSION 10.17.0

# ==============================================================
# 	blackfire args to pass into build 
#	($ docker build -t test-build:v1 --build-arg BF_SERV_ID=XXXXX)
# ==============================================================
ARG BF_SERV_ID=XXXX
ARG BF_SERV_TOKEN=XXXX
ARG BF_CLIENT_ID=XXXX
ARG BF_CLIENT_TOKEN=XXXX

ENV BLACKFIRE_SERVER_ID $BF_SERV_ID
ENV BLACKFIRE_SERVER_TOKEN $BF_SERV_TOKEN
ENV BLACKFIRE_CLIENT_ID $BF_CLIENT_ID
ENV BLACKFIRE_CLIENT_TOKEN $BF_CLIENT_TOKEN

# Update & upgrade
RUN apt-get update -y

# =======================
#   Install some stuff 
# =======================

	# ffmpeg
	RUN apt-get install ffmpeg --no-install-recommends -y

	# --------
	# dev
	# --------

	# nvm, node, npm
	RUN curl -o- https://raw.githubusercontent.com/creationix/nvm/$NVM_VERSION/install.sh | bash
	RUN chmod +x $HOME/.nvm/nvm.sh
	RUN . $HOME/.nvm/nvm.sh && nvm install $NODE_VERSION && nvm alias default $NODE_VERSION && nvm use default && npm install -g npm
	RUN ln -sf /root/.nvm/versions/node/v$NODE_VERSION/bin/node /usr/bin/nodejs
	RUN ln -sf /root/.nvm/versions/node/v$NODE_VERSION/bin/node /usr/bin/node
	RUN ln -sf /root/.nvm/versions/node/v$NODE_VERSION/bin/npm /usr/bin/npm
	# https://stackoverflow.com/questions/25899912/how-to-install-nvm-in-docker

	# grunt-cli
	RUN npm install -g grunt-cli -y

	# blackfire.io
    # RUN wget -q -O - https://packages.blackfire.io/gpg.key | APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 apt-key add - && \
	   #  echo "deb http://packages.blackfire.io/debian any main" | tee /etc/apt/sources.list.d/blackfire.list && \
	   #  apt-get update && \
	   #  apt-get install blackfire-agent && \
	   #  blackfire-agent --register --server-id=$BLACKFIRE_SERVER_ID --server-token=$BLACKFIRE_SERVER_TOKEN && \
	   #  apt-get install blackfire-php && \
	   #  /etc/init.d/blackfire-agent restart && \
	   #  blackfire config --client-id=$BLACKFIRE_CLIENT_ID --client-token=$BLACKFIRE_CLIENT_TOKEN

	# linuxbrew
	RUN apt-get install g++ locales uuid-runtime sudo --no-install-recommends -y && \
		sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
		dpkg-reconfigure locales && \
		update-locale LANG=en_US.UTF-8 && \
		useradd -m -s /bin/bash linuxbrew && \
		echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >>/etc/sudoers
	USER linuxbrew
	WORKDIR /home/linuxbrew
	ENV LANG=en_US.UTF-8 \
		PATH=/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH \
		SHELL=/bin/bash
	RUN git clone https://github.com/Homebrew/brew /home/linuxbrew/.linuxbrew/Homebrew &&  \
		mkdir /home/linuxbrew/.linuxbrew/bin && \
		ln -s ../Homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/ && \
		brew config
	USER root
	WORKDIR /

	# mkcert
	RUN apt-get install libnss3-tools -y && \
		brew install mkcert && \
		mkcert -install

	# Lynis security audit
	RUN apt-get install lynis -y

# Remove and replace default webroot dir & set PHP session handler to Redis
RUN rm -rf /usr/share/nginx/html && \
	mkdir /usr/share/nginx/web && \
	sed -i -e "s/memory_limit\s*=\s*.*/memory_limit = 256M/g" ${php_conf} && \
	sed -i -e "s/session.save_handler\s*=\s*.*/session.save_handler = redis/g" ${php_conf} && \
	sed -i -e "s/;session.save_path\s*=\s*.*/session.save_path = \"\${REDIS_PORT_6379_TCP}\"/g" ${php_conf}

# Download the latest Craft (https://craftcms.com/support/download-previous-versions)
ADD https://download.buildwithcraft.com/craft/$CRAFT_VERSION/$CRAFT_VERSION.$CRAFT_BUILD/$CRAFT_ZIP /tmp/$CRAFT_ZIP

# Extract craft to webroot & remove default tedmplate files
RUN unzip -qqo /tmp/$CRAFT_ZIP 'craft/*' -d /usr/share/nginx/ && \
    unzip -qqoj /tmp/$CRAFT_ZIP 'public/index.php' -d /usr/share/nginx/web/

# Add default nginx config
ADD ./default.conf /etc/nginx/conf.d/default.conf

# Add craft config
ADD ./config /usr/share/nginx/craft/config

# Add env file
ADD ./env.php /usr/share/nginx/

# Add SSL
RUN mkcert $DOMAIN_URL && \
	cp ./$DOMAIN_URL.pem ./etc/ssl/$DOMAIN_URL.crt && \
	cp ./$DOMAIN_URL-key.pem ./etc/ssl/$DOMAIN_URL.key

# Cleanup
RUN rm /tmp/$CRAFT_ZIP && \
	apt-get clean && apt-get autoclean && apt-get autoremove --purge && \
	rm -rf /var/lib/apt/lists/*

# Permissions
RUN chown -Rf nginx:nginx /usr/share/nginx/

EXPOSE 80
EXPOSE 443