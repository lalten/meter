#!/usr/bin/perl

# Server program for receiving data from a "SystaComfort II" control.
# To run this program you need to set up a local DNS entry for
# paradigma.remoteportal.de that points to the computer that runs this script.
#
# Copyright (c) 2013 Klaus.Schmidinger@tvdr.de.
#
# Feel free to use, modify and redistribute this software according to the
# GNU General Public License (GNU GPL).

use Getopt::Std;
use IO::Socket::INET;
use RRDs;

$Version = "0.0.5";

$Usage = qq{
Usage: $0 [options]

Options: -d       dump data bytes
         -D       print debug output
         -l       list data
         -m ADDR  send status mails to ADDR (default is "root")
         -v       be verbose
         -w COLS  print COLS columns when dumping (default is 8)
};

getopts("dDlm:vw:") || die $Usage;

$Dump    = $opt_d;
$Debug   = $opt_D;
$List    = $opt_l;
$MailTo  = $opt_m || "root";
$Verbose = $opt_v;
$Columns = $opt_w || 8;

$LOGGER   = "logger";
$SENDMAIL = "/usr/lib/sendmail -t";

$ParadigmaPort  = 22460;
$MaxDataLength  = 2048;
$CounterOffset  = 0x3FBF;
$MacOffset      = 0x8E83;
$ReplyMsgLength = 20;
$NoError        = 255;
$SocketTimeOut  = 120; # seconds, must be > 60
$MailInterval   = 24 * 3600; # only send error mails once per day

$OneWireRoomTemp = "/tmp/eclo-1wire/28.3A87A8000000/temperature";

$RrdName        = "heizung";
$RrdFile        = "$RrdName.rrd";
$VdrFile        = "$RrdName.vdr";

# Values from paradigma control:

@Mac = ();
$Aussen  = 0; # Aussentemperatur
$HeizungVorlauf = 0; # Vorlauftemperatur Heizung (ist)
$HeizungRuecklauf = 0; # Ruecklauftemperatur Heizung
$Brauchwasser = 0; # Brauchwassertemperatur (ist)
$Zirkulation = 0; # Zirkulation (ist)
$Kollektor = 0; # Kollektortemperatur (ist)
$KesselVorlauf = 0; # Vorlauftemperatur Kessel (ist)
$KesselRuecklauf = 0; # Ruecklauftemperatur Kessel
$BrauchwasserSoll = 0; # Brauchwassertemperatur (soll)
$InnenSoll = 0; # Raumtemperatur (soll)
$KesselSoll = 0; # Brauchwassertemperatur (angefordert)
$BA  = 0; # Betriebsart
$Trn = 0; # Raumtemperatur normal (soll)
$Trk = 0; # Raumtemperatur komfort (soll)
$Tra = 0; # Raumtemperatur abgesenkt (soll)
$Fusspunkt = 0; # Fusspunkt
$Steilheit = 0; # Steilheit
$TVm = 0; # Max. Vorlauftemperatur
$HeizgrenzeHeizen = 0; # Heizgrenze Heizbetrieb
$HeizgrenzeAbsenken = 0; # Heizgrenze Absenken
$Tfs = 0; # Frostschutz Aussentemperatur
$tva = 0; # Vorhaltezeit Aufheizen
$uek = 0; # Ueberhoehung Kessel
$shk = 0; # Spreizung Heizkreis
$phk = 0; # Minimale Drehzahl Pumpe PHK
$tmi = 0; # Mischer Laufzeit
$TWn = 0; # Brauchwassertemperatur normal
$TWk = 0; # Brauchwassertemperatur komfort
$Stx = 0; # status?
$Raumeinfluss = 0; # Raumeinfluss
$BrauchwasserDelta  = 0; # Brauchwasser Schaltdifferenz
$npp = 0; # Nachlauf Pumpe PK/LP
$tmk = 0; # Min. Laufzeit Kessel
$NrB = 0; # Anzahl Brennerstarts
$ZirkulationDelta = 0; # Zirkulation Schaltdifferenz
$Countdown = 0; # some countdown during the night?!
$Relais = 0; # aktive Relais
$RelaisHeizkreispumpe    = 0x0001;
$RelaisLadepumpe         = 0x0080;
$RelaisZirkulationspumpe = 0x0100;
$RelaisKessel            = 0x0200;
$Heizkreispumpe = 0;
$Ladepumpe      = 0;
$Zirkulationspumpe = 0;
$Kessel         = 0;
$Brenner        = 0;
$Fehler = $Err = 0; # Fehlerstatus (255 = OK)
$St  = 0; # status
$Innen = 0; # Raumtemperatur
@LastN = (); for ($i = 0; $i < 256; $i++) { push(@LastN, 0); }#XXX

sub Main
{
  Log("paradigma server started");
  my $Socket = new IO::Socket::INET(
       LocalPort => $ParadigmaPort,
       Proto     => "udp",
       ) or die "ERROR in socket creation: $!\n";
  my $LastPacket = 0; # time when the last valid packet was received
  while (1) {
        my @Data = Receive($Socket);
        if (@Data) {
           $LastPacket = time() if Process(@Data);
           Reply($Socket, @Data);
           }
        Check($LastPacket && (time() - $LastPacket > $SocketTimeOut), "Kein Datenpaket empfangen!", "Datenpaket empfangen.", "MailNoPacket");
        }
  $Socket->close();
}

sub Process
{
  my @a = @_;
  # 0..5: MAC address of paradigma control board:
  @Mac = ($a[3], $a[2], $a[1], $a[0], $a[5], $a[4]);
  # 6..7: counter, incremented by 1 for each packet
  # 8..15: always "09 09 0C 00 32 DA 00 00"
  # 16: packet type (00 = empty intial packet, 01 = actual data packet, 02 = short final packet)
  #XXX
 # open(F, ">>x.data");
 # printf(F "%02d:%02d ", (localtime)[2], (localtime)[1]);
 # printf(F "TAG %02X", $a[16]);
 # printf(F "\n");
 # close(F);
  #XXX
  return 0 unless $a[16] == 0x01; # we're only interested in the actual data
  # 17..23: always "00 00 00 00 00 00 00"
  # Everything from offset 24 upwards are 4 byte integers:
  my @n = AtoInt(splice(@a, 24));
  # Remember some old values:
  $FusspunktOld = $Fusspunkt;
  $SteilheitOld = $Steilheit;
  # The following is for packet type 01 only:
  $Aussen           = $n[0] / 10; # Aussentemperatur
  $HeizungVorlauf   = $n[1] / 10; # Vorlauftemperatur Heizung (ist)
  $HeizungRuecklauf = $n[2] / 10; # Ruecklauftemperatur Heizung
  $Brauchwasser     = $n[3] / 10; # Brauchwassertemperatur (ist)
  $Zirkulation      = $n[6] / 10; # Zirkulation (ist)
  $Raumtemperatur   = $n[9] / 10; # Raumtemperatur (ist)
  $Kollektor        = $n[11] / 10; # Kollektortemperatur (ist)
  $KesselVorlauf    = $n[12] / 10; # Vorlauftemperatur Kessel (ist)
  $KesselRuecklauf  = $n[13] / 10; # Ruecklauftemperatur Kessel
  $BrauchwasserSoll = $n[22] / 10; # Brauchwassertemperatur (soll)
  $InnenSoll        = $n[23] / 10; # Raumtemperatur (soll)
                    # 24 ? Heizkreislauf?
                    # 25 ?
  $KesselSoll       = $n[34] / 10; # angeforderte Kesseltemperatur
  $BA  = $n[36]; # Betriebsart (0 = Auto Prog. 1, 6 = Sommer)
                 # 37: wie 36?
  $Trn = $n[39]; # Raumtemperatur normal (soll)
  $Trk = $n[40]; # Raumtemperatur komfort (soll)
  $Tra = $n[41]; # Raumtemperatur abgesenkt (soll)
                 # 42: Status?
                 # 47: Regelung HK nach: 0=Aussentemperatur, 1=Raumtemperatur, 2= TA/TI kombiniert
  $Fusspunkt = $n[48] / 10; # Fusspunkt
                 # 49: Heizkurvenoptimierung?
  $Steilheit = $n[50] / 10; # Steilheit
                 # 51: Heizkurvenoptimierung?
  $TVm = $n[52]; # Max. Vorlauftemperatur
  $HeizgrenzeHeizen = $n[53] / 10; # Heizgrenze Heizbetrieb
  $HeizgrenzeAbsenken = $n[54] / 10; # Heizgrenze Absenken
  $Tfs = $n[55]; # Frostschutz Aussentemperatur
  $tva = $n[56]; # Vorhaltezeit Aufheizen
  $Raumeinfluss = $n[57] / 10; # Raumeinfluss
  $uek = $n[58]; # Ueberhoehung Kessel
  $shk = $n[59]; # Spreizung Heizkreis
  $phk = $n[60]; # Minimale Drehzahl Pumpe PHK
  $tmi = $n[62]; # Mischer Laufzeit
                 # 65: Raumtemperatur Abgleich (* 10, neg. Werte sind um 1 zu hoch, 0 und -1 werden beide als 0 geliefert)
  $TWn = $n[149]; # Brauchwassertemperatur normal
  $TWk = $n[150]; # Brauchwassertemperatur komfort
  $Stx = $n[151]; # Status?
  $BrauchwasserDelta = $n[155] / 10; # Brauchwasser Schaltdifferenz
  $npp = $n[158]; # Nachlauf Pumpe PK/LP
  $tmk = $n[162]; # Min. Laufzeit Kessel
                  # 179: Betriebszeit Kessel (Stunden)
                  # 180: Betriebszeit Kessel (Minuten)
                  # 169: Nachlaufzeit Pumpe PZ
  $NrB = $n[181]; # Anzahl Brennerstarts
  $ZirkulationDelta = $n[171]; # Zirkulation Schaltdifferenz
                  # 183: Solargewinn Tag???
                  # 184: Solargewinn gesamt???
  $Countdown = $n[186]; # some countdown during the night?!
  $Relais = $n[220]; # aktive Relais
  $Heizkreispumpe    = int(($Relais & $RelaisHeizkreispumpe) != 0);
  $Ladepumpe         = int(($Relais & $RelaisLadepumpe) != 0);
  $Zirkulationspumpe = int(($Relais & $RelaisZirkulationspumpe) != 0);
  $Kessel            = int(($Relais & $RelaisKessel) != 0);
  $Brenner           = $Kessel && ($KesselVorlauf - $KesselRuecklauf > 2);
                  # 222: Status?
  $Err = $n[228]; # Fehlerstatus (255 = OK)
  $Fehler = int($Err != $NoError); # w/o the int() it is an empty string instead of 0!?
                  # 230: Status?
                  # 231: Status?
  $St  = $n[232]; # Status
                  # 248: Status?
  # Report some special value changes:
  SendMail("Fusspunkt geändert ($FusspunktOld -> $Fusspunkt)") if ($FusspunktOld && $Fusspunkt != $FusspunktOld);
  SendMail("Steilheit geändert ($SteilheitOld -> $Steilheit)") if ($SteilheitOld && $Steilheit != $SteilheitOld);
  #XXX
#  open(F, ">>x.data");
#  printf(F "%02d:%02d ", (localtime)[2], (localtime)[1]);
#  for (my $i = 0; $i < $#n; $i++) {
#      printf("%3d %6d / %6d\n", $i, $n[$i], $LastN[$i]) if ($n[$i] != $LastN[$i]);
#      if ($n[$i] != $LastN[$i]) {
#         my $x = $n[$i];
#         $x = 9999 if ($x > 9999);
#         printf(F "%4d", $x);
#         }
#      else {
#         printf(F "   .");
#         }
#      }
#  printf(F "\n");
#  close(F);
  #XXX
  @LastN = @n;
  #$Innen = GetRoomTemperature();#XXX
  $Innen = $Raumtemperatur;
  List() if ($List);
  DisplayVdr();
  Check($Err != $NoError, "Fehler $Err", "Fehler behoben.", "MailError");
  UpdateRrdFile();
  GraphRrdFile();
  return 1;
}

sub List
{
  printf("MAC = %02X:%02X:%02X:%02X:%02X:%02X\n", @Mac);
  printf("Aussen  = %.1f\n", $Aussen);
  printf("HeizungVorlauf = %.1f\n", $HeizungVorlauf);
  printf("HeizungRuecklauf = %.1f\n", $HeizungRuecklauf);
  printf("Brauchwasser  = %.1f\n", $Brauchwasser);
  printf("Zirkulation  = %.1f\n", $Zirkulation);
  printf("Kollektor = %.1f\n", $Kollektor);
  printf("KesselVorlauf = %.1f\n", $KesselVorlauf);
  printf("KesselRuecklauf = %.1f\n", $KesselRuecklauf);
  printf("BrauchwasserSoll = %.1f\n", $BrauchwasserSoll);
  printf("InnenSoll = %.1f\n", $InnenSoll);
  printf("Innen = %.1f\n", $Innen);
  printf("KesselSoll = %.1f\n", $KesselSoll);
  printf("BA  = %d\n", $BA);
  printf("Trn = %.1f\n", $Trn / 10);
  printf("Trk = %.1f\n", $Trk / 10);
  printf("Tra = %.1f\n", $Tra / 10);
  printf("Fusspunkt = %.1f\n", $Fusspunkt);
  printf("Steilheit = %.1f\n", $Steilheit);
  printf("TVm = %.1f\n", $TVm / 10);
  printf("HeizgrenzeHeizen = %.1f\n", $HeizgrenzeHeizen);
  printf("HeizgrenzeAbsenken = %.1f\n", $HeizgrenzeAbsenken);
  printf("Tfs = %.1f\n", $Tfs / 10);
  printf("tva = %d\n", $tva);
  printf("uek = %.1f\n", $uek / 10);
  printf("shk = %.1f\n", $shk / 10);
  printf("phk = %d\n", $phk);
  printf("tmi = %d\n", $tmi);
  printf("TWn = %.1f\n", $TWn / 10);
  printf("TWk = %.1f\n", $TWk / 10);
  printf("Stx = %d\n", $Stx);
  printf("Raumeinfluss  = %.1f\n", $Raumeinfluss);
  printf("BrauchwasserDelta  = %.1f\n", $BrauchwasserDelta);
  printf("npp = %.1f\n", $npp / 10);
  printf("tmk = %d\n", $tmk);
  printf("NrB = %d\n", $NrB);
  printf("ZirkulationDelta  = %.1f\n", $ZirkulationDelta);
  printf("Countdown = %d\n", $Countdown);
  printf("Relais = %d\n", $Relais);
  printf("Err = %d\n", $Err);
  printf("St  = %d\n", $St);
}

sub DisplayVdr
{
  open(F, ">$VdrFile");
  printf(F "Heizung: %s\n", $Fehler ? "Fehler $Err" : "OK");
  printf(F "\n");
  printf(F "Aussen:    %5.1f°\n", $Aussen);
  printf(F "Innen:     %5.1f°\n", $Innen);
  printf(F "Wasser:    %5.1f°   %s\n", $Brauchwasser, $Ladepumpe ? "ein" : "aus");
  printf(F "Zirko:     %5.1f°   %s\n", $Zirkulation, $Zirkulationspumpe ? "ein" : "aus");
  printf(F "Kessel:    %5.1f°   %s\n", $KesselVorlauf, $Brenner ? "ein" : "aus");
  printf(F "Heizung:   %5.1f°   %s\n", $HeizungVorlauf, $Heizkreispumpe ? "ein" : "aus");
  printf(F "Kollektor: %5.1f°\n", $Kollektor) if ($Kollektor > 0);
  printf(F "\n");
  printf(F "Stand:   %s\n", `date`);
  close(F);
}

sub Reply
{
  my ($Socket, @a) = @_;
  # Limit message length and fill with zeros:
  $#a = $ReplyMsgLength - 1;
  for ($i = 8; $i <= $#a; $i++) {
      $a[$i] = 0;
      }
  # Always constant:
  $a[12] = 0x01;
  # Generate reply ID from MAC address:
  my $m = (($Mac[4] << 8) + $Mac[5] + $MacOffset) & 0xFFFF;
  $a[16] = $m & 0xFF;
  $a[17] = $m >> 8;
  # Generate reply counter with offset:
  my $n = (($a[7] << 8) + $a[6] + $CounterOffset) & 0xFFFF;
  $a[18] = $n & 0xFF;
  $a[19] = $n >> 8;
  Send($Socket, @a);
}

sub Receive
{
  my $Socket = shift;
  my $s = "";
  my $TimedOut = 0;
  eval {
    local $SIG{ALRM} = sub { $TimedOut = 1; };
    alarm($SocketTimeOut);
    $Socket->recv($s, $MaxDataLength);
    alarm(0);
    1;
    };
  return () unless Check($TimedOut, "Keine Verbindung!", "Verbindung OK.", "MailLostConnection");
  printf("received %d bytes from %s:%s\n", length($s), $Socket->peerhost(), $Socket->peerport()) if ($Verbose);
  my @a = StringToArray($s);
  Dump(@a) if ($Dump);
  return @a;
}

sub Send
{
  my ($Socket, @a) = @_;
  printf("sending %d bytes to %s:%s\n", $#a + 1, $Socket->peerhost(), $Socket->peerport()) if ($Verbose);
  Dump(@a) if ($Dump);
  $Socket->send(ArrayToString(@a));
}

sub StringToArray
{
  my $s = shift;
  my @a = ();
  my $l = length($s);
  for (my $i = 0; $i < $l; $i++) {
      $a[$i] = ord(substr($s, $i, 1));
      }
  return @a;
}

sub ArrayToString
{
  my @a = @_;
  my $s = "";
  for (my $i = 0; $i <= $#a; $i++) {
      $s .= chr($a[$i]);
      }
  return $s;
}

sub AtoInt
{
  my @a = @_;
  my @n = ();
  for (my $i = 0; $i < $#a; $i += 4) {
      my $t = $a[$i] + ($a[$i + 1] << 8) + ($a[$i + 2] << 16)+ ($a[$i + 3] << 24);
      $t -= 0xFFFFFFFF if (($a[$i + 3] & 0x80) != 0);
      push(@n, $t);
      }
  return @n;
}

sub Dump
{
  my @a = @_;
  for (my $i = 0; $i <= $#a; $i++) {
      print("\n") if ($i && ($i % $Columns) == 0);
      printf(" %02X", $a[$i]);
      }
  print("\n");
}

sub SendMail
{
  my ($Subject, $Message) = @_;
  Log($Subject);
  my $s = qq{From: Heizung
To: $MailTo
Content-Type: text/plain; charset=ISO-8859-1
Subject: $Subject

$Message
};
  open(F, "|$SENDMAIL");
  print F $s;
  close(F);
  $$LastSent = time() if ($LastSent);
}

sub Check
{
  my ($ErrorCondition, $ErrorMsg, $OkMsg, $LastReported) = @_;
  if ($ErrorCondition) {
     SendMail($ErrorMsg) unless (time() - $$LastReported < $MailInterval);
     $$LastReported = time();
     }
  else {
     SendMail($OkMsg) if ($$LastReported);
     $$LastReported = 0;
     }
  return !$ErrorCondition;
}

sub Log
{
  my $Message = shift;
  system("$LOGGER 'Heizung: $Message'");
}

# Room temerature via "one-wire":

sub GetRoomTemperature
{
  open(F, $OneWireRoomTemp);
  $s = <F>;
  close(F);
  $s =~ s/ //g;
  $s = 'U' unless Check($s eq "", "Fehler bei Abfrage der Raumtemperatur!", "Raumtemperatur-Abfrage OK.", "MailRoomTemperatur");
  return $s;
}

# RRD-Tools:

$Step = 60;
$HeartBeat = 2 * $Step;
$XFF = "0.5";
$TemperatureRange = "-40:120";
@Ranges = ("1:2160", "5:2304", "20:2502", "240:2379", "2400:2196");

         $igName = 0; $igDelta = 1; $igXGrid = 2;
%G = (
  A => [ "hours",     "-6h",        '' ],
  B => [ "day",       "-36h",       'HOUR:1:DAY:1:HOUR:2:0:%H' ],
  C => [ "week",      "-8d",        '' ],
  D => [ "month",     "-5w",        '' ],
  E => [ "year",      "-13mon",     '' ],
  F => [ "decade",    "-10y",       'MONTH:3:YEAR:1:YEAR:1:31536000:%Y' ],
  );

#XXX range für jedes extra (relais nur 0/1 etc)
#XXX rrd file anpassen!
         $idName = 0;          $idRRA = 1;        $idType = 2; $idColor = 3; $idMult = 4; $idOffset = 5; $idFmt = 6; $idNl = 7; $idStyle = 8; $idRange = 9;
%F = (#                                                         RRGGBBAA                                                                      index of %G
  A => [ "Aussen",             "AVERAGE MIN MAX", "LINE2",     "0000FF9F",   1,           0,             "%5.1lf",   1,         "",           "F" ],
  B => [ "Innen",              "AVERAGE MIN MAX", "LINE2",     "A070309F",   1,           0,             "%5.1lf",   1,         "",           "F" ],
  C => [ "InnenSoll",          "LAST",            "AREA",      "A070303F",   1,           0,             "%5.1lf",   1,         "",           "D" ],
  D => [ "Brauchwasser",       "AVERAGE MIN MAX", "LINE2",     "00FF009F",   1,           0,             "%5.1lf",   0,         "",           "F" ],
  E => [ "Ladepumpe",          "LAST",            "AREA",      "00DD44FF",   2,           77,            "%5.0lf",   1,         "",           "C" ],
  F => [ "Zirkulation",        "AVERAGE MIN MAX", "LINE2",     "FFCC559F",   1,           0,             "%5.1lf",   0,         "",           "F" ],
  G => [ "Zirkulationspumpe",  "LAST",            "AREA",      "FFCC55FF",   2,           80,            "%5.0lf",   1,         "",           "C" ],
  H => [ "BrauchwasserSoll",   "LAST",            "AREA",      "00FF001F",   1,           0,             "%5.1lf",   1,         "",           "D" ],
  I => [ "BrauchwasserDelta",  "LAST",            "AREA",      "00000000",   1,           0,             "%5.1lf",   1,         "",           "D" ],
  J => [ "Kollektor",          "AVERAGE MIN MAX", "LINE1",     "FF00009F",   1,           0,             "%5.1lf",   1,         "",           "C" ],
  K => [ "KesselSoll",         "LAST",            "AREA",      "FF8B9B6F",   1,           0,             "%5.1lf",   1,         "",           "C" ],
  L => [ "KesselVorlauf",      "AVERAGE MIN MAX", "LINE1",     "FF00009F",   1,           0,             "%5.1lf",   0,         "",           "C" ],
  M => [ "Brenner",            "LAST",            "AREA",      "FF8B9BFF",   2,           71,            "%5.0lf",   1,         "",           "C" ],
  N => [ "KesselRuecklauf",    "AVERAGE MIN MAX", "LINE1",     "0000FF9F",   1,           0,             "%5.1lf",   1,         "",           "C" ],
  O => [ "HeizungVorlauf",     "AVERAGE MIN MAX", "LINE1",     "FF00005F",   1,           0,             "%5.1lf",   0,         "",           "F" ],
  P => [ "Heizkreispumpe",     "LAST",            "AREA",      "A07030FF",   2,           74,            "%5.0lf",   1,         "",           "C" ],
  Q => [ "HeizungRuecklauf",   "AVERAGE MIN MAX", "LINE1",     "2266FF9F",   1,           0,             "%5.1lf",   1,         "",           "F" ],
  R => [ "Countdown",          "AVERAGE MIN MAX", "AREA",      "AFAFAF4F",   1,           0,             "%5.1lf",   1,         "",           "D" ],
  S => [ "Raumeinfluss",       "LAST",            "LINE1",     "00FF009F",   1,           0,             "%5.1lf",   1,         ":dashes",    "F" ],
  T => [ "Fusspunkt",          "LAST",            "LINE1",     "000000FF",   1,           0,             "%5.1lf",   1,         ":dashes",    "F" ],
  U => [ "Steilheit",          "LAST",            "LINE1",     "00FFFF9F",   10,          0,             "%5.1lf",   1,         ":dashes",    "F" ],
  V => [ "HeizgrenzeHeizen",   "LAST",            "LINE1",     "FF0000FF",   1,           0,             "%5.1lf",   1,         ":dashes",    "F" ],
  W => [ "HeizgrenzeAbsenken", "LAST",            "LINE1",     "0000FFFF",   1,           0,             "%5.1lf",   1,         ":dashes",    "F" ],
  X => [ "Fehler",             "LAST",            "AREA",      "FF0000FF",   2,           83,            "%5.0lf",   1,         "",           "C" ],
  );

sub AssertRrdFile
{
  if (!-e $RrdFile) {
     my @Cmd = ();
     push(@Cmd, $RrdFile);
     push(@Cmd, "--step", $Step);
     for (sort keys %F) {
         push(@Cmd, "DS:$F{$_}[$idName]:GAUGE:$HeartBeat:$TemperatureRange");
         for my $rra (split(' ', $F{$_}[$idRRA])) {
             for (@Ranges) {
                 push(@Cmd, "RRA:$rra:$XFF:$_");
                 }
             }
         }
     print join(' ', @Cmd) . "\n" if ($Debug);
     RRDs::create(@Cmd);
     die if (RrdError("while creating $RrdFile"));
     }
}

sub RrdError
{
  my $Msg = shift;
  my $Err = RRDs::error;
  print "ERROR $Msg: $Err\n" if ($Err);
  return $Err;
}

sub UpdateRrdFile
{
  my @ds = ();
  my @d = ('N');
  for (sort keys %F) {
      my $n = $F{$_}[$idName];
      push(@ds, $n);
      push(@d, defined($$n) ? $$n : 'U');
      }
  print join(":", @ds) . " - " . join(":", @d) . "\n" if ($Debug);
  RRDs::update($RrdFile, "--template", join(":", @ds), join(":", @d));
  die if (RrdError("while updating $RrdFile"));
}

sub GraphRrdFile
{
  my $MaxLength = 0;
  for (keys %F) {
      my $l = length($F{$_}[$idName]);
      $MaxLength = $l if ($l > $MaxLength);
      }
  for my $Range (sort keys %G) {
      my @Cmd = ();
      # general options:
      push(@Cmd, "$RrdName-$G{$Range}[$igName].png");
      push(@Cmd, "--start", $G{$Range}[$igDelta]);
      push(@Cmd, "--width", "600");
      push(@Cmd, "--height", "500");
      $Date = `date`;
      chomp($Date);
      push(@Cmd, "--title", "Heizung $Date");
      push(@Cmd, "--vertical-label", "Grad Celsius - K/K * 10");
      push(@Cmd, "--slope-mode");
      push(@Cmd, "--x-grid", $G{$Range}[$igXGrid]) if ($G{$Range}[$igXGrid]);
      push(@Cmd, "--right-axis", "1:0");
      push(@Cmd, "--right-axis-format", "%.0lf");
      #XXX push(@Cmd, "--lazy");
      # legend:
      push(@Cmd, "COMMENT:" . ' 'x$MaxLength . "        cur    min    avg    max\\n" );
      # processing:
      for (sort keys %F) {
          next if ($Range gt $F{$_}[$idRange]);
          my $Name = $F{$_}[$idName];
          my $Fmt = $F{$_}[$idFmt];
          my $Nl = $F{$_}[$idNl];
          my $rra = $F{$_}[$idRRA];
          push(@Cmd, "DEF:cur$Name=$RrdFile:$Name:LAST");
          push(@Cmd, "DEF:min$Name=$RrdFile:$Name:MIN");
          push(@Cmd, "DEF:avg$Name=$RrdFile:$Name:AVERAGE");
          push(@Cmd, "DEF:max$Name=$RrdFile:$Name:MAX");
          my $VName = "avg$Name";
          if ($F{$_}[$idMult] != 1) {
             $VName = "mul$Name";
             push(@Cmd, "CDEF:$VName=avg$Name,$F{$_}[$idMult],*");
             }
          my $ofs = $F{$_}[$idOffset];
          if ($ofs) {
             (my $Color = $F{$_}[$idColor]) =~ s/..$/4F/; # makes baseline a little weaker
             push(@Cmd, "LINE1:$ofs#$Color");
             push(@Cmd, "$F{$_}[$idType]:$VName#$F{$_}[$idColor]:$Name:STACK$F{$_}[$idStyle]");
             }
          elsif ($Name eq "BrauchwasserSoll") {
             # Draw a horizontal bar, displaying the requested range of the hot water:
             push(@Cmd, "DEF:bwd=$RrdFile:BrauchwasserDelta:AVERAGE");
             push(@Cmd, "CDEF:lo$Name=avg$Name,bwd,-,0,MAX");
             push(@Cmd, "CDEF:hi$Name=avg$Name,40,GT,bwd,0,IF"); # no bar if no hot water is requested ('40' is necessary to avoid "ghosts" in month display)
             push(@Cmd, "LINE1:lo$Name");
             push(@Cmd, "$F{$_}[$idType]:hi$Name#$F{$_}[$idColor]:$Name:STACK");
             }
          elsif ($Name eq "Aussen" || $Name eq "Innen" || $Name eq "Brauchwasser") {
             (my $Color = $F{$_}[$idColor]) =~ s/..$/4F/; # makes range a little weaker
             push(@Cmd, "CDEF:lo$Name=min$Name,avg$Name,-,0,MIN");
             push(@Cmd, "CDEF:hi$Name=max$Name,avg$Name,-,0,MAX");
             push(@Cmd, "LINE1:avg$Name");
             push(@Cmd, "AREA:lo$Name#${Color}::STACK");
             push(@Cmd, "LINE1:avg$Name");
             push(@Cmd, "AREA:hi$Name#${Color}::STACK");
             push(@Cmd, "$F{$_}[$idType]:avg$Name#$F{$_}[$idColor]:$Name$F{$_}[$idStyle]");
             }
          else {
             push(@Cmd, "$F{$_}[$idType]:$VName#$F{$_}[$idColor]:$Name$F{$_}[$idStyle]");
             }
          my $Align = ' 'x($MaxLength - length($Name));
          push(@Cmd, "GPRINT:cur$Name:LAST:$Align $Fmt");
          push(@Cmd, "GPRINT:min$Name:MIN:$Fmt") if ($rra =~ /MIN/);
          push(@Cmd, "GPRINT:avg$Name:AVERAGE:$Fmt") if ($rra =~ /AVERAGE/);
          push(@Cmd, "GPRINT:max$Name:MAX:$Fmt") if ($rra =~ /MAX/);
          push(@Cmd, "COMMENT:\\n") if ($Nl || $Range gt "B");
          }
      # actual drawing:
      print join("\n", @Cmd) . "\n" if ($Debug);
      RRDs::graph(@Cmd);
      RrdError("while graphing $RrdFile");
      }
}

AssertRrdFile();
Main();