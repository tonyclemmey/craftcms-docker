# ==============================================================
#	Notes:
#	1) This is an experimental docker build for develoment / testing purposes.
#	2) Arguments set so far can be parsed into the build for USER, GROUP, SITE URL & BLACKFIRE
# ==============================================================
FROM php:7.4-apache
MAINTAINER Tony Clemmey "tonyclemmey@gmail.com"
ENV DEBIAN_FRONTEND noninteractive

# ==============================================================
# 	Replacing the internal user/group IDs with known, good values
# 	Host system first user with 1000:1000 after root 0:0 (SFTP Docker Volumes)
# 	https://jtreminio.com/blog/running-docker-containers-as-current-host-user/#ok-so-what-actually-works
# ==============================================================
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN userdel -f www-data && \
    if getent group www-data ; then groupdel www-data; fi && \
    groupadd -g ${GROUP_ID} www-data && \
    useradd -l -u ${USER_ID} -g www-data www-data && \
    install -d -m 0755 -o www-data -g www-data /home/www-data && \
    chown --changes --silent --no-dereference --recursive \
      --from=33:33 ${USER_ID}:${GROUP_ID} \
    /home/www-data \
    /var/www

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

# =======================
#   Install some stuff
# =======================
	RUN apt-get update && \
		apt-get install -y --no-install-recommends \
		apt-utils \
		software-properties-common \
		zip \
		unzip \
		nano \
		ffmpeg \
		g++ \
		git \
		locales \
		uuid-runtime \
		sudo \
		libnss3-tools \
		lynis

	# Easily install PHP extension in Docker containers (https://github.com/mlocati/docker-php-extension-installer)
	COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/bin/

	# Install required php extenstions
	RUN install-php-extensions imagick gd mcrypt intl redis

	# nvm, node, npm (https://stackoverflow.com/questions/25899912/how-to-install-nvm-in-docker)
	RUN curl -o- https://raw.githubusercontent.com/creationix/nvm/$NVM_VERSION/install.sh | bash && \
		chmod +x $HOME/.nvm/nvm.sh && \
		. $HOME/.nvm/nvm.sh && nvm install $NODE_VERSION && nvm alias default $NODE_VERSION && nvm use default && npm install -g npm && \
		ln -sf /root/.nvm/versions/node/v$NODE_VERSION/bin/node /usr/bin/nodejs && \
		ln -sf /root/.nvm/versions/node/v$NODE_VERSION/bin/node /usr/bin/node && \
		ln -sf /root/.nvm/versions/node/v$NODE_VERSION/bin/npm /usr/bin/npm

	# grunt-cli
	RUN npm install -g grunt-cli -y

	# linuxbrew
	RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
		dpkg-reconfigure locales && \
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
	RUN brew install mkcert && \
		mkcert -install

# Remove and replace default webroot dir
RUN rm -rf /var/www/html && \
mkdir /var/www/web

# Enable the Apache SSL module
RUN a2enmod ssl

# Add SSL
RUN mkcert $DOMAIN_URL && \
	cp ./$DOMAIN_URL.pem ./etc/ssl/$DOMAIN_URL.crt && \
	cp ./$DOMAIN_URL-key.pem ./etc/ssl/$DOMAIN_URL.key

# Download the latest Craft (https://craftcms.com/support/download-previous-versions)
ADD https://download.buildwithcraft.com/craft/$CRAFT_VERSION/$CRAFT_VERSION.$CRAFT_BUILD/$CRAFT_ZIP /tmp/$CRAFT_ZIP

# Extract craft to webroot & remove default tedmplate files
RUN unzip -qqo /tmp/$CRAFT_ZIP 'craft/*' -d /var/www && \
  unzip -qqoj /tmp/$CRAFT_ZIP 'public/index.php' -d /var/www/web

# Add craft config
ADD ./config /var/www/craft/config

# Add Apache config
ADD ./000-default.conf /etc/apache2/sites-enabled

# Cleanup
RUN	apt-get clean && apt-get autoclean && apt-get autoremove --purge && \
	rm -rf /var/lib/apt/lists/*

# Permissions
RUN chown -Rf www-data:www-data /var/www

EXPOSE 80
EXPOSE 443

CMD ["/usr/sbin/apache2ctl", "-D",  "FOREGROUND"]
