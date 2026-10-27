Container Belege Upload abgleichen:

cd /home/chegl

sudo docker compose up -d --build --force-recreate viseca-upload

sudo docker exec viseca-upload ls /app     # erwartet: app.py bank_check.py viseca_parser.py
