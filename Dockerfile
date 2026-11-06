# Stage 1: Construcción del libro
FROM rust:1.77 AS builder

# Instalar mdbook
RUN cargo install mdbook

# Copiar el contenido del libro al contenedor
WORKDIR /app
COPY . .

# Construir el libro
RUN mdbook build

# Stage 2: Servir el libro con Nginx
FROM nginx:alpine

# Copiar los archivos generados por mdbook en la primera etapa
COPY --from=builder /app/book /usr/share/nginx/html

# Exponer el puerto 80 para Nginx
EXPOSE 80

# Comando por defecto para iniciar Nginx
CMD ["nginx", "-g", "daemon off;"]