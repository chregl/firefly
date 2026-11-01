Container Belege Upload abgleichen:

cd /home/chegl

sudo docker compose up -d --build --force-recreate viseca-upload

sudo docker exec viseca-upload ls /app     # erwartet: app.py bank_check.py viseca_parser.py


Ablauf

Der Button legt /control/trigger/backup.now an (auf dem Host /home/chegl/control/trigger/).
Die systemd-Path-Unit startet firefly-backup-web.sh als root. Es verbraucht die Trigger-Datei und ruft firefly_backup.sh backup auf.
Die Seite fragt alle 2 s den Status ab und zeigt die Log-Zeilen live an.
Nach Erfolg wird die Checkbox automatisch gesetzt, und die Buttons «Abgleichen» werden aktiv. Bei einem Fehler bleibt sie leer.

Änderungen in app.py

Neue Endpunkte POST /backup/start und GET /backup/status.
Doppelstarts werden mit 409 abgewiesen.
Meldet der Host nach 30 s nichts, räumt die App die Trigger-Datei auf und zeigt einen Hinweis zur Path-Unit.
«Abgleichen» wird serverseitig blockiert, solange ein Backup läuft.
Die Checkbox bleibt als manueller Fallback bestehen.
Compose und Dockerfile sind unverändert, das Volume /control genügt.

Installation auf srv01

bash
unzip viseca-upload.zip -d /tmp/vu
sudo /tmp/vu/viseca-upload/host/install-host.sh
# App-Dateien in dein Projektverzeichnis kopieren (v.a. app.py), dann:
cd /home/chegl && docker compose up -d --build viseca-upload

Das Install-Skript legt das Trigger-Verzeichnis an, kopiert Wrapper und Units und aktiviert firefly-backup-web.path. Vor dem ersten Klick kannst du es direkt testen:

bash
touch /home/chegl/control/trigger/backup.now
journalctl -u firefly-backup-web -f

Zu prüfen

Pfad des Backup-Skripts: Der Wrapper nutzt firefly_backup.sh aus dem PATH und sonst /home/chegl/firefly_backup.sh. Liegt es woanders, passe die Variable BACKUP oben in firefly-backup-web.sh an.
Container-Stopp: Stoppt das Backup-Skript Container, darunter viseca-upload, bricht die Anzeige kurzzeitig ab. Der Status liegt auf dem Host, deshalb zeigt die Seite nach dem Neustart den laufenden oder fertigen Lauf weiter an.
Rechte: Der Container läuft als uid 1000 und kann damit nur die Trigger-Datei anlegen. Welcher Befehl als root läuft, ist fest im Wrapper hinterlegt.
Log: Das vollständige Log des letzten Laufs liegt in /var/log/firefly-backup-web.log. Die Weboberfläche zeigt nur die letzten 60 Zeilen.
ufw: Es sind keine neuen Regeln nötig.
