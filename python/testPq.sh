#!/bin/sh
pw=/etc/passwd; pwHdr=logname:pw:uid:gid:fullName:home:shell
seq 0 1000000|pq -w'len(row)<2'
pq -d: 'print(s[1],s[0])' <$pw
pq -d: -bt=0 t+=nf -e'print(t)' <$pw
pq -d: -bt=0 -w'i(2)>0' 't+=i(2)' -e'print(t)' <$pw
echo 2 | pq 'x=f(0)' 'print((1+x)/x)'
(echo $pwHdr; cat $pw) | pq -d: -f$pwHdr 'print(s[logname],s[uid])'
pq -d: -mremoved -f$pwHdr -bt=0 't+=i(uid)' -e'print(t)' <$pw
echo 4 | pq -pimport\ math 'print(math.sqrt(f(0)) - f(0)**0.5)'
