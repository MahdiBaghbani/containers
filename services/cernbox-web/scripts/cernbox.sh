#!/usr/bin/env sh

file_path="/var/www/web/config.json"
web_original="your.nginx.org"
web_replacement="${CERNBOX_WEB_HOSTNAME}"
idp_original="your-idp.org:your-idp-port"
idp_replacement="${CERNBOX_IDP_HOSTNAME}:${CERNBOX_IDP_PORT}"

sed -i "s#${web_original}#${web_replacement}#g" "${file_path}"
sed -i "s#${idp_original}#${idp_replacement}#g" "${file_path}"
