# Dockerfile
FROM nginx:alpine
WORKDIR /usr/share/nginx/html

# Remove default static files
RUN rm -rf ./*

# Copy the pre-built files
COPY dist/ .

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
