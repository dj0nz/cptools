## My private Check Point knowledge base ##

I use these scripts at work and wanted to make them public available. Maybe some of you can benefit from them. 
That would make me very happy. Feel free to contact me if you find any serious mistakes.

### add-gw-hostnames.sh
Uses mgmt_cli to fetch names of gateways or cluster members from Check Point database and creates host name entries. 

### backup-gaia-mgmt.sh
Enhanced management server backup. Does backup AND export, adds version info, gaia config and some directories to a tgz and copies the bundle using scp to a given backup server.
