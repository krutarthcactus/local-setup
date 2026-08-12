FROM nginx:1.27-alpine

# Remove default config; ours is mounted via docker-compose volumes at
# /etc/nginx/conf.d/local.scr.com.conf, but keep the image self-contained
# in case someone builds it standalone.
RUN rm -f /etc/nginx/conf.d/default.conf

# Log directory permissions — nginx runs as `nginx` user inside the container
RUN mkdir -p /var/log/nginx && chown -R nginx:nginx /var/log/nginx
