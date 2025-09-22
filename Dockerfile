FROM node:18-alpine AS builder

WORKDIR /app

# Copy package.json first for better Docker layer caching
COPY package.json ./

# Install dependencies (all dependencies needed for build)
RUN npm ci --silent && npm cache clean --force

# Copy source files maintaining proper directory structure
COPY public/ ./public/
COPY src/ ./src/

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
    # Security headers \
    add_header X-Frame-Options "SAMEORIGIN" always; \
    add_header X-XSS-Protection "1; mode=block" always; \
    add_header X-Content-Type-Options "nosniff" always; \
    \
    # Gzip compression \
    gzip on; \
    gzip_vary on; \
    gzip_min_length 1024; \
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript; \
    \
    # React app routing \
    location / { \
        try_files $uri $uri/ /index.html; \
        expires 1h; \
        add_header Cache-Control "public, immutable"; \
    } \
    \
    # Static assets caching \
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ { \
        expires 1y; \
        add_header Cache-Control "public, immutable"; \
    } \
    \
    # API proxy \
    location /api/ { \
        proxy_pass http://api-gateway:8000/; \
        proxy_set_header Host $host; \
        proxy_set_header X-Real-IP $remote_addr; \
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; \
        proxy_set_header X-Forwarded-Proto $scheme; \
        proxy_connect_timeout 60s; \
        proxy_send_timeout 60s; \
        proxy_read_timeout 60s; \
        proxy_buffering off; \
    } \
    \
    # Health check endpoint \
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
