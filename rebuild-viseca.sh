cat > ~/rebuild-viseca.sh <<'EOF'
#!/bin/bash
set -e
cd /home/chegl
IMG=$(docker compose config --images | grep viseca)
docker buildx bake -f docker-compose.yml --allow network.host --load \
  --set "viseca-upload.tags=$IMG" viseca-upload
docker compose up -d --force-recreate viseca-upload
EOF
chmod +x ~/rebuild-viseca.sh
