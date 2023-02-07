#!/bin/bash
#
# Loeschen unbenutzer Host-Objekte aus der Check Point Datenbank
# Als Eingabe wird der CSV-Export aus Tufin SecureTrack ("Unattached Network Objects") erwartet 
#
# dj0Nz 2020

INFILE=$1
LOGFILE=hosts-purge.log

cat /dev/null > $LOGFILE

if [ $1 = "" ]; then
   echo "Usage: parse.sh <input file>"
   exit 1
fi

if [[ -f $INFILE && -s $INFILE ]]; then
   cat $INFILE | grep ^\"Host  | tr -d '"' | awk -F , '{print $2}' > $INFILE.tmp
else
   echo "No valid input file"
   exit 1
fi

mgmt_cli login session-name "Mgmt CLI" session-description "Delete unused hosts" > id.txt

while read line; do
   USED=`mgmt_cli where-used name "$line" -s id.txt | grep total | awk -F : '{print $2}' | awk '{$1=$1};1' | tr -d '\r'`
   if [ "$USED" == "0" ]; then
      echo "Object $line is not used, deleting..."
      mgmt_cli delete host name "$line" -s id.txt
   else
      echo "Object $line used somewhere. Adding record to logfile."
	  mgmt_cli where-used name "$line" --format json -s id.txt >> $LOGFILE 
   fi
done < $INFILE.tmp

echo ""
echo "Done. Cleaning up."
rm $INFILE.tmp
mgmt_cli publish -s id.txt
mgmt_cli logout -s id.txt
rm id.txt