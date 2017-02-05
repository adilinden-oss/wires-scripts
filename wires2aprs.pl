#!/usr/bin/perl
#
# To install on Windows:
#
# Install Strawberry perl available at:
#   http://strawberryperl.com
#
# Install modules needed for this script
#   C:\> cpanm install Ham::APRS::IS
#
# Create batch file to run this script.  Batch file needs fill path to perl
# interpreter and full path to this script.  Something like:
#   c:\Strawberry\perl\bin\perl.exe c:%HOMEPATH%\Documents\wires2aprs\wires2aprs.pl
#
# Create a task in task scheduler
#   Open task scheduler via Start Menu
#     Select Action > Create Basic Task...
#       Name: Wires-X to APRS
#       Trigger: Daily
#       Accept default time
#       Start a Program
#       Select our batch file
#       Check: Open Properties dialog for this task...
#       Finish
#     Select Trigger tab
#       Edit trigger
#         Repeat task every 3 minutes, Indefinitely
#         Enable
#
# Just a note for future implementations, WiresWeb.dll is a plugin that enables access to
# Log via web interface.  To access the webinterface with password:
#   http://localhost:46190/?wipassword=jones
#
# Enabling the web interface:
#
#    Tool(T) > Plugin set
#      AddModule
#        WiresWeb.dll
#
#    Tool(T) > WIRES WebServer
#      Access password    :    jones
#      Port No.           :    46190
#      Remote Control     :    check
#
#    Now accessible via 
#      http://localhost:46190/?wipassword=jones
#

use strict;
use warnings;

use Time::Local;
use Ham::APRS::IS;

# Global debug switch
my $debug = 1;

# Call to symbol table
#
# This table defines the call signs we filter on.  APRS limits callsign
# to a maximum of 9 charachters (6 characters plus SSID).
#
my %call_to_symbol = (
    "N0CALL-7"      => "/[", 
    "N0CALL-9"      => "/>", 
    "N0CALL-14"     => "/k", 
    );

# Our Wires-X access log
my $wireslog = "$ENV{HOMEPATH}/Documents/WIRESXA/AccHistory/WiresAccess.log";

# APRS specific
my $aprs_call = "N0CALL-YS";
my $aprs_pass = "99999";

# Anything older then $expire seconds is ignore
# Recommend this to be equal to time between script executions
my $expire = 5 * 60;

# Connect to APRS-IS
my $aprs_is = aprs_open();
if (!$aprs_is) { die "Could not connect to APRS-IS!"; }

# Parse file
open(my $fh, '<:encoding(UTF-8)', $wireslog)
    or die "Could not open file '$wireslog' $!";

# Dump current time
print localtime(time()) . "\n";

while (my $line = <$fh>) {

    my $regex;
    my $aprslat;
    my $aprslon;

    # Skip any non conforming lines
    # Format: 9 values delimited with %
    $line =~ /^([^%]*%){9}$/ or next;

    # Parse line into variables
    my ($userid,$dtmf,$call,$heard,$source,$unknown1,$coord,$unknown2,$coordtime) = split(/%/, $line);

    unless (exists $call_to_symbol{$call}) {
        print "= Skip: $call =\n";
        next;
    }

    if ($debug) {
        print "==== New Call ====\n";
        print "$userid\n";
        print "$dtmf\n";
        print "$call\n";
        print "$heard\n";    
        print "$source\n";    
        print "$coord\n";
        print "----- Result -----\n";
    }

    # Parse coordinates
    # Example: N:39 08' 34" / W:077 10' 03"
    $regex = '^([NS]):(\d+) (\d+)\' (\d+)" / ([EW]):(\d+) (\d+)\' (\d+)"$';
    if ($coord =~ m!$regex!) {
        my $yyy = $1;
        my $ydd = $2;
        my $ymm = $3;
        my $yss = $4;
        my $xxx = $5;
        my $xdd = $6;
        my $xmm = $7;
        my $xss = $8;

        # Convert to APRS coordinates
        $aprslat = two_wide($ydd) . mmss_to_dec($ymm, $yss) . $yyy;
        $aprslon = three_wide($xdd) . mmss_to_dec($xmm, $xss) . $xxx;

        if ($debug) {
            print "$aprslat\n";
            print "$aprslon\n";
        }

    } else {
        if ($debug) { print "Invalid or missing coordinates\n"; }
        next;
    }

    # Parse date
    # Example: 2017/01/07 21:26:05
    $regex = '^(\d+)/(\d+)/(\d+) (\d+):(\d+):(\d+)$';
    if ($heard =~ m!$regex!) {
        my $yea = $1;
        my $mon = $2;
        my $day = $3;
        my $hou = $4;
        my $min = $5;
        my $sec = $6;

        # See if heard timestamp is too old
        # epoch from date time parts: 
        #       timelocal($sec, $min, $hou, $day, $mon - 1, $yea)
        # epoch now: 
        #       time()
        if ($expire + timelocal($sec, $min, $hou, $day, $mon - 1, $yea) > time()) {
            aprs_beacon($aprs_is, $call, $aprslat, $aprslon);
        } else {
            if ($debug) { print "Timestamp older than $expire seconds\n"; }
        }
    } else {
        if ($debug) { print "Invalid or missing timestamp\n"; }
        next;
    }
}

# Finished
aprs_close($aprs_is);

# Connect to APRS-IS
sub aprs_open {
    my $is = new Ham::APRS::IS(
        'rotate.aprs.net:14580', 
        $aprs_call,
        'passcode' => $aprs_pass,
        'appid' => 'IS-pm-test 1.0');
    $is->connect('retryuntil' => 3) || return 0;
    return $is;
}

# Disconnect from APRS-IS
sub aprs_close {
    my ($is) = @_;
    $is->disconnect() || return 0;
    return 1;
}

# Send to APRS-IS
#
# See APRS Protocol Reference for details on packet structure
# http://www.aprs.org/doc/APRS101.PDF 
#
sub aprs_beacon {
    my ($is, $call, $lat, $lon) = @_;

    my $packet;

    # Construct packet, start with header
    $packet =  "$call>APRS,TCPIP*:";

    # Add latitude without messaging capability
    $packet .= "!$lat";

    # Add symbol table
    $packet .= substr($call_to_symbol{$call}, 0, 1);

    # Add longitude
    $packet .= "$lon";

    # Add symbol code
    $packet .= substr($call_to_symbol{$call}, 1, 1);

    # Add comment
    $packet .= "via Wires-X $aprs_call";

    if ($debug) { print "Packet: $packet\n"; }

    $is->sendline($packet);
}

# Convert minutes and seconds to decimal
sub mmss_to_dec {
    my ($mm, $ss) = @_;

    # Seconds divided to obtain decimal
    my $out = $mm + $ss / 60;

    # 5 wide, 2 positions after decimal
    $out = sprintf("%05.2f", $out);

    return $out;
}

# 2 wide
sub two_wide {
    my ($in) = @_;

    # 2 wide
    return sprintf("%02d", $in);
}

# 3 wide
sub three_wide {
    my ($in) = @_;

    # 3 wide
    return sprintf("%03d", $in);
}
