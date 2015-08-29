#!/usr/bin/python

# process data output of paradigma-server.pl -l and send it to an emoncms installation

import fileinput
import requests
import time

baseurl = "https://laurenz.gacrux.uberspace.de/emoncms/input/bulk.json"
nid = "2" # node id

arr = {"Kollektor":0, "Aussen":0, "Innen":0}

while True:
    for line in fileinput.input():
        line = line.replace(" ", "") # strip all spaces
        line = line.replace("\n", "") # strip all spaces
        parts = line.partition("=")
        if parts[0] in arr.keys(): # we only want to send interesting data
#            print parts[0] + ": " + parts[2]
            arr[parts[0]]=parts[2]
        if parts[0] == "St": # the last line
            url=baseurl \
			+"?data=[[0,"+nid+","+arr["Kollektor"]+","+arr["Aussen"]+","+arr["Innen"]+"]]" \
			+"&apikey=XXX"
            try:
                r = requests.get(url)
                # print url + " --> " + str(r.status_code)
            except Exception:
                import traceback
                print traceback.format_exc() 
	time.sleep(0.1)