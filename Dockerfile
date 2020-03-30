FROM wyveo/nginx-php-fpm:php74

MAINTAINER Colin Wilson "colin@wyveo.com"

# Set craft cms version
ENV CRAFT_VERSION=2.9 CRAFT_BUILD=2

ENV CRAFT_ZIP=Craft-$CRAFT_VERSION.$CRAFT_BUILD.zip

# Install ffmpeg
RUN apt-get update -y && \
	apt-get install ffmpeg -y && \
	apt-get clean all

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

# Install Linux-brew
RUN apt-get install build-essential curl file git
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)"

# Add Linux-brew to your ~/.bashrc by running
RUN echo 'export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin/:$PATH"' >>~/.bashrc && \
echo 'export MANPATH="/home/linuxbrew/.linuxbrew/share/man:$MANPATH"' >>~/.bashrc && \
echo 'export INFOPATH="/home/linuxbrew/.linuxbrew/share/info:$INFOPATH"' >>~/.bashrc && \
source  ~/.bashrc && \
brew help

# Install and copy mkcert certificates
RUN apt-get install libnss3-tools -y && \
brew install mkcert && \
mkcert -install && \
mkcert mysite.test && \
cp ./mysite.test.cert.pem ./etc/ssl/mysite.test.crt && \
cp ./mysite.test-key.pem ./etc/ssl/mysite.test.key

# Add default config
ADD ./config /usr/share/nginx/craft/config

# Cleanup
RUN rm /tmp/$CRAFT_ZIP && \
chown -Rf nginx:nginx /usr/share/nginx/

# Check versions
RUN ffmpeg -version
RUN php -v
RUN php -m

EXPOSE 80
EXPOSE 443