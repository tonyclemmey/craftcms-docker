FROM wyveo/nginx-php-fpm:php74
MAINTAINER Colin Wilson "colin@wyveo.com"

# Set craft cms version
ENV CRAFT_VERSION=2.9 CRAFT_BUILD=2
ENV CRAFT_ZIP=Craft-$CRAFT_VERSION.$CRAFT_BUILD.zip

# Set domain / server name
ENV DOMAIN_URL=mysite.test

### Install some stuff ###
RUN apt-get update -y && \
	# ffmpeg
	apt-get install ffmpeg --no-install-recommends -y &&  \
	# linuxbrew
	apt-get install ca-certificates curl file g++ git locales make uuid-runtime --no-install-recommends -y && \
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
	mkcert -install && \
	# Lynis security audit
	apt-get install lynis -y

# Remove and replace default webroot dir & set PHP session handler to Redis
RUN rm -rf /usr/share/nginx/html && \
	mkdir /usr/share/nginx/web && \
	sed -i -e "s/memory_limit\s*=\s*.*/memory_limit = 256M/g" ${php_conf} && \
	sed -i -e "s/session.save_handler\s*=\s*.*/session.save_handler = redis/g" ${php_conf} && \
	sed -i -e "s/;session.save_path\s*=\s*.*/session.save_path = \"\${REDIS_PORT_6379_TCP}\"/g" ${php_conf}

# Download the latest Craft (https://craftcms.com/support/download-previous-versions)
ADD https://download.buildwithcraft.com/craft/$CRAFT_VERSION/$CRAFT_VERSION.$CRAFT_BUILD/$CRAFT_ZIP /tmp/$CRAFT_ZIP

# Extract craft to webroot & remove default template files
RUN unzip -qqo /tmp/$CRAFT_ZIP 'craft/*' -d /usr/share/nginx/ && \
    unzip -qqoj /tmp/$CRAFT_ZIP 'public/index.php' -d /usr/share/nginx/web/

# Add default nginx config
ADD ./default.conf /etc/nginx/conf.d/default.conf

# Add default craft cms config
ADD ./config /usr/share/nginx/craft/config

# Add SSL
RUN mkcert $DOMAIN_URL && \
	cp ./$DOMAIN_URL.pem ./etc/ssl/$DOMAIN_URL.crt && \
	cp ./$DOMAIN_URL-key.pem ./etc/ssl/$DOMAIN_URL.key

# Cleanup
RUN rm /tmp/$CRAFT_ZIP && \
	apt-get clean all && \
	rm -rf /var/lib/apt/lists/*

# Permissions
RUN chown -Rf nginx:nginx /usr/share/nginx/

EXPOSE 80
EXPOSE 443

# https://docs.docker.com/develop/develop-images/dockerfile_best-practices/