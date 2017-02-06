#!/usr/bin/perl
#
# Copyright 2017 Adi Linden <adi@adis.ca>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Notes:
# ======
#
# To install on Windows:
#
# Install Strawberry perl available at:
#   http://strawberryperl.com
#
# Install modules needed for this script
#   C:\> cpanm install HTTP::Tiny
#   C:\> cpanm install Config::Tiny
#

use strict;
use warnings;

use Time::Local;
use Config::Tiny;
use Getopt::Std;
use Ham::APRS::IS;

##
## Global Variables
##

# Script information
my %script = (
    wiresx      => '1.120',
    name        => 'wires2aprs.pl',
    version     => '0.9',
    author      => 'Adi Linden <adi@adis.ca>',
    license     => 'GPLv3 <http://www.gnu.org/licenses/>',
    github      => 'https://github.com/adilinden/wires-scripts/',
);

# Callsign filter
my %filter;

# Running configuration
my %cfg;

# Default configuration
my %cfg_default = (
    aprsis      => {
        callsign    => 'N0CALL-YS',
        password    => '12345',
    },
    wiresx      => {
        accesslog   => "%HOMEPATH%/Documents/WIRESXA/AccHistory/WiresAccess.log",
    },
);

# Script defaults (overridden by command line args)
my $debug       = "0";
my $quiet       = "0";
my $oneshot     = "0";
my $interval    = "60";
my $cfgfile     = "wires2aprs.cfg";

##
## Main Script
##

# Process command line args
my %args;
unless (getopts('dqoi:c:shv', \%args)) {
    do_log(1, "Error", "getopts", "Unknown option");
    exit;
}

$debug = 1 if defined $args{d};
$quiet = 1 if defined $args{q};
$oneshot = 1 if defined $args{o};
$interval = $args{i} if defined $args{i};
$cfgfile = $args{c} if defined $args{c};
sample() if defined $args{s};
usage() if defined $args{h};
version() if defined $args{v};

if ($debug) {
    use Data::Dumper;
}


exit;
# End of new

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

# New functions

sub do_log {
    my ($l, $f, $m, $v) = @_;

    # Log levels
    #
    # 1 - Error
    # 2 - Inform
    # 3 - Debug

    return if ($quiet and $l > 1);
    return if (! $debug and $l > 2);

    print "${f}: " if defined $f and length $f;
    print "${m}: " if defined $m and length $m;
    print "${v} " if defined $v and length $v;
    print "\n";
}

sub usage {
    print "\nUsage: $script{name} [-dhoqsv] [-c configfile] [-i seconds]\n";
    print "  -c file          configuration file\n";
    print "  -d               debug information\n";
    print "  -h               display usage\n";
    print "  -o               one-shot run only once\n";
    print "  -q               quiet, suppress all output\n";
    print "  -s               display default configuration\n";
    print "  -v               display version\n";
    print "  -i seconds       interval in seconds to run\n\n";
    print "Supports:  Wires-X $script{wiresx}\n";
    print "Version:   $script{version}\n";
    print "Author:    $script{author}\n";
    print "License:   $script{license}\n";
    print "Github:    $script{github}\n\n";
    exit;
}

sub version {
    print "$script{version}\n";
    exit;
}

sub sample {
    print qq{#
# The sample configuration file for wires2aprs.pl
#

#
# The following path substutions are supported:
#
# %HOMEPATH%    current users home directory
#

# Wires webserver access
[wiresx]
accesslog   = $cfg_default{wiresx}{accesslog}

# APRS-IS login
[aprsis]
callsign    = $cfg_default{aprsis}{callsign}
password    = $cfg_default{aprsis}{password}

# Call signs that we filter
#
# See symbol table
# http://wa8lmf.net/miscinfo/APRSsymbolcodes.txt
# http://wa8lmf.net/aprs/APRS_symbols.htm
#
# overlay = which overlay of symbols to use, should be either / or \
# symbol  = symbol to use from symbol table
#
# Coordinates can be entered.  This is useful for stations that do not
# transmit coordinates, such as the FTM-3200, and are
# fixed stations.
#
[N0CALL-0]
iscall      = yes
overlay     = /
symbol      = -
latitude    = 43.806111
longitude   = -81.273889

[N0CALL-7]
iscall      = yes
overlay     = /
symbol      = [

[N0CALL-9]
iscall      = yes
overlay     = /
symbol      = >

[N0CALL-14]
iscall      = yes
overlay     = /
symbol      = k
};
    exit;
}

# End
