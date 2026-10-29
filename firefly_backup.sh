#!/bin/bash
# firefly_backup.sh
# Vollständiges FireflyIII Backup/Restore mit Versionserkennung und Image-Caching
# PiHole, wg-easy, Caddy und DuckDNS laufen während Backup/Restore durch.

# 🔧 Basis-Pfade
DB_PATH="/var/lib/fireflyiii/mysql"
STORAGE_PATH="/var/lib/fireflyiii/storage"
OPENVPN_PATH="/var/lib/openvpn-as"
BACKUP_DIR="/var/backups/firefly"
SOURCE_DIR="/var/backups/sources"
KEEP_DAYS=30
COMPOSE_DIR="/home/chegl"
UPLOAD_PATH="/var/lib/fireflyiii/upload"

# 🔧 Services, die fürs Backup/Restore gestoppt werden
# (pihole, wg-easy, caddy, duckdns laufen weiter)
SERVICES="viseca-upload fireflyiii_cron phpmyadmin fireflyiii db"

# 🔧 Image-Definitionen
FIREFLY_IMAGE="fireflyiii/core:version-6.4.9"
MARIADB_IMAGE="mariadb:11"

# 🔧 Version aus Image holen
FIREFLY_VERSION=$(echo "$FIREFLY_IMAGE" | cut -d: -f2)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/firefly_backup_${FIREFLY_VERSION}_$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR" "$SOURCE_DIR"

cleanup_old_backups() {
    echo "🗑️  Alte Backups löschen (> $KEEP_DAYS Tage)..."
    find "$BACKUP_DIR" -type f -name "firefly_backup_*.tar.gz" -mtime +$KEEP_DAYS -exec rm -v {} \;
    find "$BACKUP_DIR" -type f -name "pihole_teleporter_*.zip" -mtime +$KEEP_DAYS -exec rm -v {} \;
}

ensure_sources_exist() {
    echo "🔍 Prüfe, ob Images im Source-Verzeichnis vorhanden sind..."

    if [ ! -f "$SOURCE_DIR/fireflyiii_core_${FIREFLY_VERSION}.tar" ]; then
        echo "⬇️  Lade FireflyIII Image ($FIREFLY_IMAGE) aus dem Internet..."
        sudo docker pull "$FIREFLY_IMAGE"
        sudo docker save -o "$SOURCE_DIR/fireflyiii_core_${FIREFLY_VERSION}.tar" "$FIREFLY_IMAGE"
    else
        echo "✅ FireflyIII Image bereits lokal vorhanden."
    fi

    if [ ! -f "$SOURCE_DIR/mariadb_11.tar" ]; then
        echo "⬇️  Lade MariaDB Image ($MARIADB_IMAGE) aus dem Internet..."
        sudo docker pull "$MARIADB_IMAGE"
        sudo docker save -o "$SOURCE_DIR/mariadb_11.tar" "$MARIADB_IMAGE"
    else
        echo "✅ MariaDB Image bereits lokal vorhanden."
    fi
}

backup_pihole() {
    echo "🕳️  Sichere PiHole-Konfiguration (Teleporter)..."
    local target="$BACKUP_DIR/pihole_teleporter_${TIMESTAMP}.zip"
    local tmpzip

    if sudo docker exec -w /tmp pihole pihole-FTL --teleporter >/dev/null 2>&1; then
        tmpzip=$(sudo docker exec pihole sh -c 'ls -t /tmp/pi-hole_*teleporter*.zip 2>/dev/null | head -1')
        if [ -n "$tmpzip" ]; then
            sudo docker cp "pihole:$tmpzip" "$target"
            sudo docker exec pihole rm -f "$tmpzip"
            echo "✅ PiHole-Export: $target"
            return 0
        fi
    fi
    echo "⚠️  PiHole-Export fehlgeschlagen (läuft der Container?), Backup läuft trotzdem weiter."
}

backup() {
    echo "🔹 Starte FireflyIII Backup (Version $FIREFLY_VERSION)..."
    backup_pihole

    cd "$COMPOSE_DIR"
    sudo docker compose stop $SERVICES

    ensure_sources_exist

    echo "🗂️  Sichere Datenverzeichnisse..."
    sudo tar -czf "$BACKUP_FILE" \
        "$DB_PATH" \
        "$STORAGE_PATH" \
        "$UPLOAD_PATH" \
        "$OPENVPN_PATH"

    echo "🚀 Starte Container wieder..."
    sudo docker compose start $SERVICES
    cleanup_old_backups

    echo "✅ Backup abgeschlossen: $BACKUP_FILE"
}

restore() {
    if [ -z "$1" ]; then
        echo "❌ Bitte Backup-Datei angeben: ./firefly_backup.sh restore <backup-file>"
        exit 1
    fi

    BACKUP_TO_RESTORE="$1"
    if [ ! -f "$BACKUP_TO_RESTORE" ]; then
        echo "❌ Backup-Datei nicht gefunden: $BACKUP_TO_RESTORE"
        exit 1
    fi

    # Version aus Backup-Dateiname extrahieren
    RESTORE_VERSION=$(basename "$BACKUP_TO_RESTORE" | sed -E 's/^firefly_backup_(version-[0-9]+\.[0-9]+\.[0-9]+)_.*/\1/')

    echo "♻️  Stelle Backup wieder her (Version $RESTORE_VERSION)..."
    cd "$COMPOSE_DIR"
    sudo docker compose stop $SERVICES

    echo "📦 Entpacke Backup..."
    sudo tar -xzf "$BACKUP_TO_RESTORE" -C /

    echo "⬆️  Lade passende Docker-Images..."
    if [ -f "$SOURCE_DIR/fireflyiii_core_${RESTORE_VERSION}.tar" ]; then
        echo "✅ Lade FireflyIII Image aus Source-Verzeichnis..."
        sudo docker load -i "$SOURCE_DIR/fireflyiii_core_${RESTORE_VERSION}.tar"
    else
        echo "⚠️  FireflyIII Image nicht lokal, lade online..."
        sudo docker pull "fireflyiii/core:$RESTORE_VERSION" || {
            echo "❌ Fehler: FireflyIII Version $RESTORE_VERSION nicht gefunden!"
            exit 1
        }
    fi

    if [ -f "$SOURCE_DIR/mariadb_11.tar" ]; then
        echo "✅ Lade MariaDB Image aus Source-Verzeichnis..."
        sudo docker load -i "$SOURCE_DIR/mariadb_11.tar"
    else
        echo "⚠️  MariaDB Image nicht lokal, lade online..."
        sudo docker pull "$MARIADB_IMAGE"
    fi

    echo "🧹 Berechtigungen korrigieren..."
    sudo chown -R 1000:1000 "$STORAGE_PATH"
    sudo chmod -R 775 "$STORAGE_PATH"
    sudo chown -R 1000:1000 "$UPLOAD_PATH"
    sudo chmod -R 775 "$UPLOAD_PATH"

    echo "🚀 Starte Container..."
    sudo docker compose up -d --no-build --no-recreate $SERVICES
    sleep 5

    echo "🧼 FireflyIII Cache & Migration..."
    sudo docker exec -u root fireflyiii chown -R www-data:www-data /var/www/html/storage
    sudo docker exec -u root fireflyiii chmod -R 775 /var/www/html/storage
    sudo docker exec -it fireflyiii php artisan cache:clear || true
    sudo docker exec -it fireflyiii php artisan config:clear || true
    sudo docker exec -it fireflyiii php artisan view:clear || true
    sudo docker exec -it fireflyiii php artisan migrate --force || true

    echo "✅ Restore abgeschlossen (Version $RESTORE_VERSION)"
    echo "ℹ️  PiHole wurde nicht angefasst. Config bei Bedarf über Settings → Teleporter einspielen."
}

case "$1" in
    backup)
        backup
        ;;
    restore)
        restore "$2"
        ;;
    *)
        echo "Usage: $0 {backup|restore <backup-file>}"
        exit 1
        ;;
esac
