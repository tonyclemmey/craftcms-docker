FROM wyveo/nginx-php-fpm:php74
MAINTAINER Colin Wilson "colin@wyveo.com"

# Set craft cms version
ENV CRAFT_VERSION=2.9 CRAFT_BUILD=2
ENV CRAFT_ZIP=Craft-$CRAFT_VERSION.$CRAFT_BUILD.zip

### Install some stuff ###
RUN apt-get update -y && \
	apt-get upgrade -y && \
	# ffmpeg
	apt-get install ffmpeg --no-install-recommends -y &&  \
	# linuxbrew
	apt-get install build-essential ruby-full locales --no-install-recommends -y
	RUN localedef -i en_US -f UTF-8 en_US.UTF-8
	RUN useradd -m -s /bin/bash linuxbrew && \
	    echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >>/etc/sudoers
	USER linuxbrew
	RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)"
	USER root
	ENV PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"
	# mkcert
	RUN apt-get install libnss3-tools -y && \
	brew install mkcert && \
	mkcert -install

# Remove default webroot files & set PHP session handler to Redis
RUN rm -rf /usr/share/nginx/html/* && \
	mkdir /usr/share/nginx/web && \
	sed -i -e "s/memory_limit\s*=\s*.*/memory_limit = 256M/g" ${php_conf} && \
	sed -i -e "s/session.save_handler\s*=\s*.*/session.save_handler = redis/g" ${php_conf} && \
	sed -i -e "s/;session.save_path\s*=\s*.*/session.save_path = \"\${REDIS_PORT_6379_TCP}\"/g" ${php_conf}

# Download the latest Craft (https://craftcms.com/support/download-previous-versions)
ADD https://download.buildwithcraft.com/craft/$CRAFT_VERSION/$CRAFT_VERSION.$CRAFT_BUILD/$CRAFT_ZIP /tmp/$CRAFT_ZIP

# Extract craft to webroot & remove default template files
RUN unzip -qqo /tmp/$CRAFT_ZIP 'craft/*' -d /usr/share/nginx/ && \
    unzip -qqoj /tmp/$CRAFT_ZIP 'public/index.php' -d /usr/share/nginx/web/

# Add default craft cms nginx config
ADD ./default.conf /etc/nginx/conf.d/default.conf

# Add default config
ADD ./config /usr/share/nginx/craft/config

# Add SSL
RUN mkcert mysite.test && \
	cp ./mysite.test.pem ./etc/ssl/mysite.test.crt && \
	cp ./mysite.test-key.pem ./etc/ssl/mysite.test.key

# Cleanup
RUN rm /tmp/$CRAFT_ZIP && \
	apt-get clean all && \
	rm -rf /var/lib/apt/lists/*

# Permissions
RUN chown -Rf nginx:nginx /usr/share/nginx/

# Check stuff
RUN ffmpeg -version && \
	php -v && \
	php -m && \
	brew list

EXPOSE 80
EXPOSE 443