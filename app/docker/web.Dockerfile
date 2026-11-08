FROM nginx:1.27-alpine
COPY app/web/index.html app/web/styles.css app/web/app.js /usr/share/nginx/html/
COPY app/web/nginx.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 8080
