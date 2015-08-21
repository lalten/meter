# meter
This project's goal is to read data from an electric meter and present it in pleasant form in a web frontend.

# Overview

Components
 * Eltako [DSZ12D](http://www.eltako.com/fileadmin/downloads/de/_bedienung/DSZ12D_28365612-1_internet_dtsch.pdf) electric meter
 * ESP8266 WiFi module
  

# Setup
 * Install the Arduino IDE with Esp8266 support as per https://github.com/esp8266/Arduino
 * As of [now](https://github.com/esp8266/Arduino/issues/268#issuecomment-111174573), you need to use either the staging release or build from git to use the OTA update infrastructure: http://arduino.esp8266.com/staging/package_esp8266com_index.json
 * Make sure to select the ESP8266 in the Tools>Board menu.

## First time flashing
Connect the ESP8266 module to your serial adapter. Pinout and functions:

```
In       3V3
/BOOT    /RESET
GPIO     /PWRDWN
GND      Out
```

| Pin | Usage |
| --- | -------- |
| In | UART input |
| 3V3 | VCC |
| /BOOT | Pull up to VCC |
| /RESET | Pull up to VCC |
| GPIO | ? |
| /PWRDWN | Pull up to VCC |
| GND | Ground |
| Out | UART output |

To be able to flash via UART, keep /BOOT low while triggering a reset by strobing /RESET low.

## OTA flashing

In Arduino IDE preferences turn on verbose output for "upload".  
When you upload your sketch it will show you the command line its using and more importantly "where" it's decided to put the .bin file, for [people](http://www.esp8266.com/viewtopic.php?p=20942#p20942) on windows it's in *C:\Users\Laurenz\AppData\Local\Temp\build4391113069216900671.tmp/webupdate.cpp.bin*
