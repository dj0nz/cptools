#!/bin/bash

PROXY=""

check_url () {
    RESULT=" [ ERROR ]"
    NAME="$2 "
    while [ ${#NAME} -lt 74 ]; do NAME="$NAME."; done
    echo -en "$NAME "
    if [[ $PROXY ]]; then
        RESPONSE=$(curl --proxy $PROXY -LiskI $1 | grep "HTTP/1.1" | awk 'END { print }')
    else
        RESPONSE=$(curl -LiskI $1 | grep "HTTP/1.1" | awk 'END { print }')
    fi
    STATUS=$(echo "${RESPONSE}" | awk 'END { print $2 " " $3 " " $4}')
    STATUS_CODE=$(echo ${RESPONSE} | awk '{ print $2 }')
    if [ "${STATUS_CODE}" != "200" ]; then
        echo "${RESULT} - Got HTTP ${STATUS_CODE}"
    else RESULT=" [ OK ]"
        echo "${RESULT}"
    fi
}

echo
echo "Prüfe Verbindungen zum Check Point Usercenter"
echo "Siehe http://supportcontent.checkpoint.com/solutions?id=sk83520"
echo

check_url 'http://cws.checkpoint.com/APPI/SystemStatus/type/short' 'Social Media Widget Detection'
check_url 'http://cws.checkpoint.com/URLF/SystemStatus/type/short' 'URL Filtering Cloud Categorization'
check_url 'http://cws.checkpoint.com/AntiVirus/SystemStatus/type/short' 'Virus Detection'
check_url 'http://cws.checkpoint.com/Malware/SystemStatus/type/short' 'Bot Detection'
check_url 'https://updates.checkpoint.com/' 'IPS Updates and Updatable Objects'
check_url 'http://crl.globalsign.com' 'CRL Globalsign'
check_url 'http://dl3.checkpoint.com' 'Download Service Updates '
check_url 'https://usercenter.checkpoint.com/usercenter/services/ProductCoverageService' 'Contract Entitlement '
check_url 'https://usercenter.checkpoint.com/usercenter/services/BladesManagerService' 'Software Blades Manager Service'
check_url 'http://resolver1.chkp.ctmail.com' 'Suspicious Mail Outbreaks'
check_url 'http://download.ctmail.com' 'Anti-Spam'
check_url 'http://te.checkpoint.com/tecloud/Ping' 'Threat Emulation'
check_url 'http://teadv.checkpoint.com' 'Threat Emulation Advanced'
check_url 'https://threat-emulation.checkpoint.com/tecloud/Ping' 'Threat Emulation'
check_url 'https://ptcs.checkpoint.com' 'PTC Updates'
check_url 'http://kav8.zonealarm.com/version.txt' 'Deep inspection'
check_url 'http://kav8.checkpoint.com' 'Traditional Anti-Virus'
check_url 'http://avupdates.checkpoint.com/UrlList.txt' 'Traditional Anti-Virus, Legacy URL Filtering'
check_url 'http://sigcheck.checkpoint.com/Siglist2.txt' 'Download of signature updates'
check_url 'http://secureupdates.checkpoint.com' 'Manage Security Gateways'
check_url 'https://productcoverage.checkpoint.com/ProductCoverageService' 'Makes sure the machines contracts are up-to-date'
check_url 'https://sc1.checkpoint.com/sc/images/checkmark.gif' 'Download of icons and screenshots from Check Point media storage servers'
check_url 'https://sc1.checkpoint.com/za/images/facetime/large_png/60342479_lrg.png' 'Download of icons and screenshots from Check Point media storage servers'
check_url 'https://sc1.checkpoint.com/za/images/facetime/large_png/60096017_lrg.png' 'Download of icons and screenshots from Check Point media storage servers'
check_url 'https://push.checkpoint.com/push/ping' 'Push Notifications '
check_url 'http://downloads.checkpoint.com' 'Download of Endpoint Compliance Updates'
check_url 'http://productservices.checkpoint.com' 'Next Generation Licensing'
echo
