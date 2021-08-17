#!/bin/bash

# Zweck:
# - sshd Verschlüsselung einstellen / Konfiguration korrigieren
# - Unsichere SSL Verschlüsselungs-Algorithmen für Gaia Portal deaktivieren
#
# Achtung: Dies gilt nur für Systeme ab R80.40 mit JHF83.
# Systeme mit einer niedrigeren Version bitte aktualisieren!
# Für R81.x gibts zum Teil andere Verfahren (ssh Ciphers in der clish etc.),
# daher bitte auf solchen Systemen nicht ungeprüft übernehmen.
#
# Kontrolle der sshd Konfiguration mit sshd -T | grep "\(ciphers\|macs\)"
# Für das Prüfen der SSL Ciphers/Protokolle hab ich ein extra-Skript (siehe Repo)
#
# Informationen:
# Siehe http://supportcontent.checkpoint.com/solutions?id=sk106031
# Siehe http://supportcontent.checkpoint.com/solutions?id=sk147272
#
# Michael Goessmann Matos, NTT, August 2021

CPVERSION=`cat /etc/cp-release | awk '{print $4}'`
JUMBO=`cpinfo -y all 2>&1 | grep -A 1 SecurePlatform | grep HOTFIX | awk '{print $3}'`
CHECK=`grep 'Macs hmac-sha2-256,hmac-sha2-512' /etc/ssh/templates/sshd_config.templ`

if [[ "$CPVERSION" == "R80.40" ]]; then
   if [[ $JUMBO -gt 82 ]]; then
      if [[ -n $CHECK ]]; then
         echo "SSH: Datei bereits modifiziert, bitte prüfen."
         exit 1
      fi
   else
      echo "Jumbo Hotfix zu alt."
      exit 1
   fi
else
   echo "Check Point Version zu alt oder zu neu."
   exit 1
fi

# Sicherheitskopie erstellen
cp /etc/ssh/templates/sshd_config.templ /home/admin/sshd_config.templ.bak

# Schwache Key Exchange Algorithmen (SHA1) entfernen
sed -i '/^Kex.*sha1/d' /etc/ssh/templates/sshd_config.templ

# Unsinnige "Match Address" und "PasswordAuth" Einträge korrigieren
sed -i '/^Match address 0.0.0.0\/0/d' /etc/ssh/templates/sshd_config.templ
if [[ -n `grep ^PasswordAuthentication.no /etc/ssh/templates/sshd_config.templ` ]]; then
   sed -i '/^[[:space:]]PasswordAuthentication yes/d' /etc/ssh/templates/sshd_config.templ
   sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/templates/sshd_config.templ
fi

# Verschlüsselungsalgorithmen einstellen
sed -i 's/^Ciphers.*/Ciphers aes256-ctr,aes256-gcm@openssh.com/g' /etc/ssh/templates/sshd_config.templ
sed -i '$ a Macs hmac-sha2-256,hmac-sha2-512' /etc/ssh/templates/sshd_config.templ

# Konfiguration aktivieren
/bin/sshd_template_xlate < /config/active
echo ""
service sshd restart

# SSL Ciphers

CHECK=`grep 'SSLProtocol -ALL TLSv1.2' /web/templates/httpd-ssl.conf.templ`

if [[ -n $CHECK ]]; then
   echo "SSL: Datei bereits modifiziert, bitte prüfen."
   exit 1
fi

# Sicherheitskopie erstellen
cp /web/templates/httpd-ssl.conf.templ /home/admin/httpd-ssl.conf.templ.bak

# Verschlüsselungsalgorithmen einstellen
chmod 600 /web/templates/httpd-ssl.conf.templ
sed -i 's/HIGH\:\!RC4\:\!LOW\:\!EXP\:\!aNULL\:\!SSLv2\:\!MD5/ECDHE-RSA-AES256-SHA384\:AES256-SHA256\:\!ADH\:\!EXP\:RSA\:+HIGH\:+MEDIUM\:\!MD5\:\!LOW\:\!NULL\:\!SSLv2\:\!eNULL\:\!aNULL\:\!RC4\:\!SHA1/g' /web/templates/httpd-ssl.conf.templ
sed -i 's/^SSLProtocol.*/SSLProtocol -ALL TLSv1.2/g' /web/templates/httpd-ssl.conf.templ
chmod 400 /web/templates/httpd-ssl.conf.templ

# Konfiguration aktivieren
/bin/template_xlate : /web/templates/httpd-ssl.conf.templ /web/conf/extra/httpd-ssl.conf < /config/active
tellpm process:httpd2
tellpm process:httpd2 t
