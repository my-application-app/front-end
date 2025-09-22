FROM node:18-alpine AS builder

WORKDIR /app

# Copy package.json first for better Docker layer caching
COPY package.json ./

# Install dependencies (use npm install since no package-lock.json exists)
RUN npm install --silent && npm cache clean --force

# Copy source files maintaining proper directory structure
COPY public/ ./public/ ./src/ ./src/

# Set build arguments and environment
ARG REACT_APP_API_URL=/api
ENV REACT_APP_API_URL=$REACT_APP_API_URL \
    NODE_ENV=production

# Build the application
RUN npm run build

# Production stage with nginx
FROM nginx:1.25-alpine

# Copy built files and configure everything in one optimized layer
COPY --from=builder /app/build /usr/share/nginx/html
RUN echo 'server { \
    listen 3000; \
    server_name localhost; \
    root /usr/share/nginx/html; \
    index index.html; \
    \
    location / { \
        try_files $uri $uri/ /index.html; \
        expires 1h; \
        add_header Cache-Control "public, immutable"; \
    } \
    \
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ { \
        expires 1y; \
        add_header Cache-Control "public, immutable"; \
    } \
    \
    location /api/ { \
        proxy_pass http://api-gateway:8000/; \
        proxy_set_header Host $host; \
        proxy_set_header X-Real-IP $remote_addr; \
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; \
        proxy_set_header X-Forwarded-Proto $scheme; \
    } \
    \
    location /health { \
        access_log off; \
        return 200 "healthy\\n"; \
        add_header Content-Type text/plain; \
    } \
}' > /etc/nginx/conf.d/default.conf && \
    rm -f /etc/nginx/conf.d/default.conf.template && \
    addgroup -g 1001 -S nginxuser && \
    adduser -S -D -H -u 1001 -h /var/cache/nginx -s /sbin/nologin -G nginxuser nginxuser && \
    chown -R nginxuser:nginxuser /usr/share/nginx/html /var/cache/nginx /var/log/nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown nginxuser:nginxuser /var/run/nginx.pid

USER nginxuser
EXPOSE 3000

CMD ["nginx", "-g", "daemon off;"]
