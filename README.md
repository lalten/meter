# meter
This project's goal is to read data from an electric meter and present it in pleasant form in a web frontend.

# Overview

Components
 * Eltako [DSZ12D](http://www.eltako.com/fileadmin/downloads/de/_bedienung/DSZ12D_28365612-1_internet_dtsch.pdf) electric meter
 * ESP8266 WiFi module
  

# Setup
 * Install the Arduino IDE with Esp8266 support (see below)
 * Make sure to select the ESP8266 in the Tools>Board menu.

## Arduino IDE
I chose to install the latest ESP8266-enabled Arduino IDE from source, because it provides neat OTA update features.
 * *git clone https://github.com/esp8266/Arduino.git* as detailed on https://github.com/esp8266/Arduino
 * Install Ant from https://code.google.com/p/winant/  
Note that you [need](https://github.com/arduino/Arduino/issues/3276) to use a 32bit [JDK](http://www.oracle.com/technetwork/java/javase/downloads/jdk8-downloads-2133151.html) with it (otherwise the successfully compiled arduino_debug.exe prints the error ..."\lib\AStylej.dll: Can't load IA 32-bit .dll on a AMD 64-bit platform" in a terminal).  
 * I ran into issues with the xtensa-toolchain .tgz file. With *which tar.exe* I found out that in my case *C:\WinAVR-20100110\utils\bin\tar.exe* (GNU tar 1.13.19) was used. I replaced the file with [bsdtar.exe](https://code.google.com/p/i18n-zh/downloads/detail?name=bsdtar.exe) (renamed to tar.exe) in the same directory.
The result is the file [arduino-1.6.6-windows.zip](arduino-1.6.6-windows.zip)  

## First time flashing
Connect the ESP8266 module to your serial adapter. Pinout and functions:

```
In       3V3
/BOOT    /RESET
GPIO2    /PWRDWN
GND      Out
```

| Pin | Id    | Usage |
| --- | ----- | ----- |
| In  | GPIO3 | UART input / S0 input |
| 3V3 | VCC | VCC |
| /BOOT | GPIO0 | Pull up to VCC |
| /RESET | RESET | Pull up to VCC |
| GPIO | GPIO2 | - |
| /PWRDWN | CHPD | Pull up to VCC |
| GND | GND | Ground |
| Out | GPIO1 | UART output |

To be able to flash via UART, keep /BOOT low while triggering a reset by strobing /RESET low.

## OTA flashing

In Arduino IDE preferences turn on verbose output for "upload":  
When you upload your sketch it will show you the command line its using and more importantly "where" it's decided to put the .bin file, for [people](http://www.esp8266.com/viewtopic.php?p=20942#p20942) on windows it's in *C:\Users\Laurenz\AppData\Local\Temp\build12345678901234567890.tmp/webupdate.cpp.bin*

Size setting is *1M (64kb)* as per [#708](https://github.com/esp8266/Arduino/issues/708)

So far, uploading doesn't go further than:  
Terminal:
```
"C:\Program Files (x86)\Arduino\hardware\esp8266com\esp8266/tools/espota.py" 192.168.1.110 8266 C:\Users\Laurenz\AppData\Local\Temp\build6191624719240643593.tmp/webupdate.ino.cpp.bin
Starting on 0.0.0.0:48266
Upload size: 308576
Sending invitation to: 192.168.1.110
Waiting for device...

Uploading..................................
Error Uploading
```
Serial:
```
Arduino OTA Test<\r><\n>
Sketch size: 308564<\n>
Free size: 651264<\n>
IP address: 192.168.1.110<\r><\n>
Update Start: ip:192.168.1.115, port:48266, size:308576<\n>
<\r><\n>
Exception (0):<\r><\n>
epc1=0x4022ae0c epc2=0x00000000 epc3=0x00000000 excvaddr=0x00000000 depc=0x00000000<\r><\n>
<\r><\n>
ctx: sys <\r><\n>
sp: 3ffffda0 end: 3fffffb0 offset: 01a0<\r><\n>
<\r><\n>
>>>stack>>><\r><\n>
3fffff40:  402171dd 3ffeb270 3ffeabe0 00000001  <\r><\n>
3fffff50:  402172c0 3ffeb274 3ffeabe0 01133053  <\r><\n>
3fffff60:  4021731c ffffffff 3ffeb048 3ffeead8  <\r><\n>
3fffff70:  402114b1 ffffffff 00000000 00000001  <\r><\n>
3fffff80:  402114f6 3fffdab0 00000000 3fffdcb0  <\r><\n>
3fffff90:  3ffeabf8 3ffeb480 00000001 40201795  <\r><\n>
3fffffa0:  40000f49 40000f49 3fffdab0 40000f49  <\r><\n>
<<<stack<<<<\r><\n>
<\r><\n>
 ets Jan  8 2013,rst cause:2, boot mode:(3,6)<\r><\n>
<\r><\n>
load 0x4010f000, len 1264, room 16 <\r><\n>
tail 0<\r><\n>
chksum 0x42<\r><\n>
csum 0x42<\r><\n>
~ld<\n>

```

Relevant tickets:
 * https://github.com/esp8266/Arduino/issues/268
 * https://github.com/esp8266/Arduino/issues/517
 * https://github.com/esp8266/Arduino/issues/708

# Display #

There are various services that offer IOT data collection, analyzation and visualization; however all of them are rate limited or not free. The ESP8266 will propably generate about 1 sample per 3 seconds (1200W average). https://thingspeak.com/ limits you to a 15s rate. http://emoncms.org/ limits to 10s rates, but allows sending more than one sample at a time, using [bulk mode](http://emoncms.org/input/api)!

Relevant:
 * [how the time parameter works in bulk mode](http://openenergymonitor.org/emon/node/3027)





# Paradigma Heating #

(work in progress)

 * ftp://ftp.tvdr.de/heizung
 * http://www.vdr-portal.de/board79-international/board83-off-topic/119690-heizungssteuerung-daten-auslesen


Get the original IP:
```sh
PARADIGMA_SERVER=$(host paradigma.remoteportal.de | awk '{ print $(NF) }')
```
Reroute all their packets to another IP:
```sh
MY_SERVER=192.168.1.1
sudo iptables -t nat -A PREROUTING -d $PARADIGMA_SERVER -j DNAT --to-destination $MY_SERVER
```
