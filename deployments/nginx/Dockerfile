# Version nginx fixé.
# Système d'exploitation figé: Alpine Linux Minimal
FROM nginx:1.29.8-alpine

# Déclaration de l'argument pour le fichier de conf
# Par défaut, si rien n'est passé au build,
# on prend nginx.conf qui est le modé sécurisé (HTTPS/443)
ARG NGINX_CONF_FILE=nginx.conf

# Nettoyage de la configuration par défaut d'usine
RUN rm /etc/nginx/conf.d/default.conf

# Injecter la configuration (Prod ou Debug selon l'ARG)
# NB : certificats PAS copiés ici, ils passeront par les volumes
# COPY ${NGINX_CONF_FILE} /etc/nginx/nginx.conf
# Lors du build le fichier est copié dans ce répertoire avec ce nom
COPY ${NGINX_CONF_FILE} /etc/nginx/templates/nginx.conf.template

# Lors du démarrage, réveil du script d'entrée (entrypoint) de l'image Nginx.
# Présence d'un fichier dans /etc/nginx/templates/ et donc commande envsubst
# démarrée pour remplacer la variable présente dans nginx.conf par son contenu
# que Docker Compose lui a transmise (défini dans service nginx / environnement)
# Ensuite le ficher modifié est copié dans nginx.config dans le répertoire spécifié
# ci-dessous. Crucial sinon il va par défaut dans /etc/nginx/conf.d/
ENV NGINX_ENVSUBST_OUTPUT_DIR=/etc/nginx

# Documentation des ports (Informatif pour Docker)
# Indiquer que l'écoute se fait sur ces ports IN
EXPOSE 80
EXPOSE 443

# Lancement de Nginx en mode premier plan (obligatoire pour Docker)
CMD ["nginx", "-g", "daemon off;"]
