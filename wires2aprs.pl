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
#   C:\> cpanm install IO::Socket::Timeout
#   C:\> cpanm install Config::Tiny
#

use strict;
use warnings;

use Time::Local;
use Config::Tiny;
use Getopt::Std;
use File::HomeDir;
use IO::Socket;
use IO::Socket::Timeout;

##
## Global Variables
##

# Use IO::Socket::Timeout if true, otherwise tries non-blocking IO.
my $use_socket_timeout = 1;

# Script information
my %script = (
    name        => 'wires2aprs.pl',
    version     => '0.9',
    wiresx      => '1.120',
    author      => 'Adi Linden <adi@adis.ca>',
    license     => 'GPLv3 <http://www.gnu.org/licenses/>',
    github      => 'httpos://github.com/adilinden/wires-scripts/',
);

# Callsign filter
my %calls;

# Callsign timestamps
my %last_heard;         # on APRS-IS
my %last_beacon;        # here

# Configuration (with default values)
my %cfg = (
    aprsis      => {
        server      => 'noam.aprs2.net',
        port        => '14580',
        callsign    => 'N0CALL-YS',
        password    => '12345',
        comment     => 'via Wires-X'
    },
    wiresx      => {
        accesslog   => "%HOMEPATH%/Documents/WIRESXA/AccHistory/WiresAccess.log",
    },
    script      => {
        expire      => 180,
        beacon      => 120,
        interval    => 60,
    },
);

# Script defaults (overridden by config file and command line args)
my $debug       = "0";
my $quiet       = "0";
my $oneshot     = "0";
my $expire      = "180";
my $beacon      = "120";
my $interval    = "60";
my $cfgfile     = "wires2aprs.cfg";

# Handle for APRS-IS connection
my $aprsis;

##
## Main Script
##

# Process command line args
my %args;
unless (getopts('b:c:de:hi:oqsv', \%args)) {
    do_log(1, "Error", "getopts", "Unknown option");
    exit;
}

sample() if defined $args{s};
usage() if defined $args{h};
version() if defined $args{v};

$debug = 1 if defined $args{d};
$quiet = 1 if defined $args{q};
if ($debug) {
    use Data::Dumper;
}

# Handle configuration file
$cfgfile = $args{c} if defined $args{c};
load_config();

$beacon = $cfg{script}{beacon} if (exists $cfg{script}{beacon});
$expire = $cfg{script}{expire} if (exists $cfg{script}{expire});
$interval = $cfg{script}{interval} if (exists $cfg{script}{interval});

$oneshot = 1 if defined $args{o};
$beacon = $args{b} if defined $args{b};
$expire = $args{e} if defined $args{e};
$interval = $args{i} if defined $args{i};

# Set timer values to some sensible first run values
my $rectmr = 0;                         # APRS-IS reconnect timer
my $logtmr = time() - $interval + 2;    # Log scan interval timer

# The main loop which runs forever unless 'oneshot' specified
while (1) {

    # Connect to APRS-IS, or reconnect
    if (! $aprsis and $rectmr + 10 < time()) {
        aprs_connect();
        $rectmr = time();
    }

    # Get line from APRS-IS
    if ($aprsis) {
        aprs_read();
    }

    # Handle WiresAccess.log
    if ($aprsis and $logtmr + $interval < time()) {
        handle_wireslog();
        $logtmr = time();

        # End now if asked to run once only
        if ($oneshot) {
            aprs_close();
            last;
        }
    }

    #do_log(2, "main", "executed", scalar localtime());

    # Pace ourselves
    sleep(1) unless ($use_socket_timeout);
}

sub handle_wireslog {
    my $func = "handle_wireslog";
    do_log(2, $func, "run at", scalar localtime());

    # Open log
    #
    # File structure
    #
    # User_ID%Radio_ID%Call%Last_Received%Recv_CH%??%Last_Position%??%??%
    my $accesslog = replace_path_variables($cfg{wiresx}{accesslog});
    my $fh;
    if (! open($fh, "<:encoding(UTF-8)", $accesslog)) {
        do_log(1, $func, "", "Could not open file '$accesslog' $!");
        return;
    }

    # Parse log
    my @wxl;
    while (<$fh>) {
        push @wxl, [ split(/%/) ];
    }

    # Close log
    close($fh);

    # Parse log
    for my $wxll (@wxl) {
        # $wxll is pointer to row of @wxl array

        # Parse line into variables
        #
        # @$wxll[0] User_ID
        # @$wxll[1] Radio_ID
        # @$wxll[2] Call
        # @$wxll[3] Last_Received
        # @$wxll[4] Recv_CH
        # @$wxll[5] ??
        # @$wxll[6] Last_Position
        # @$wxll[7] ??
        # @$wxll[8] ??
        #my @wxll = split(/%/, $line);

        # Match call with filter
        unless (exists $calls{@$wxll[0]}) {
            do_log(3, $func, "skip", "@$wxll[0] not in filter");
            next;
        }

        # Make sure overlay and symbol are defined
        unless (defined $calls{@$wxll[0]}{overlay}) {
            do_log(3, $func, "skip", "@$wxll[0] overlay not defined");
            next;
        }
        unless (defined $calls{@$wxll[0]}{symbol}) {
            do_log(3, $func, "skip", "@$wxll[0] symbol not defined");
            next;
        }


        do_log(3, $func, "- - - - - - -", "");
        do_log(3, $func, "user id      ", "@$wxll[0]");
        do_log(3, $func, "radio id     ", "@$wxll[1]");
        do_log(3, $func, "call         ", "@$wxll[2]");
        do_log(3, $func, "last received", "@$wxll[3]");
        do_log(3, $func, "last position", "@$wxll[6]");
        do_log(3, $func, "- - - - - - -", "");

        my $re;

        # Parse date
        # Example: 2017/01/07 21:26:05
        $re = '^(\d+)/(\d+)/(\d+) (\d+):(\d+):(\d+)$';
        my @lhs = @$wxll[3] =~ m!$re!;

        # Parse coordinates
        # Example: N:39 08' 34" / W:077 10' 03"
        $re = '^([NS]):(\d+) (\d+)\' (\d+)" / ([EW]):(\d+) (\d+)\' (\d+)"$';
        my @lps = @$wxll[6] =~ m!$re!;

        # - Got date?
        #   - No: Nothing further to do
        # - Date older than expire?
        #   - Yes: Nothing further to do
        # - Heard sooner than beacon interval?
        #   - Yes: Nothing further to do
        # - Got Posit?
        #   - Yes: Convert posit to APRS and fire away
        #   - No:
        #     - Got lat/lon in filter?
        #       - No:  Nothing further todo
        #       - Yes: Convert posit to APRS and fire away

        # We need at least a last heard time stamp
        unless (@lhs) {
            do_log(3, $func, "skip", "@$wxll[0] has no date");
            next;
        }

        # Calculate time from lastheard and determine if expired (too old)
        if ($expire + timelocal($lhs[5], $lhs[4], $lhs[3], $lhs[2], $lhs[1] - 1, $lhs[0]) < time()) {
            do_log(3, $func, "skip", "@$wxll[0] timestamp older than $expire seconds");
            next;
        }

        # See if we heard on APRS-IS
        if (exists $last_heard{@$wxll[0]} and $beacon + $last_heard{@$wxll[0]} > time()) {
            do_log(3, $func, "skip", "@$wxll[0] heard on APRS-IS less than $beacon seconds ago");
            next;
        }

        # See if we already beaconed recently
        if (exists $last_beacon{@$wxll[0]} and $beacon + $last_beacon{@$wxll[0]} > time()) {
            do_log(3, $func, "skip", "@$wxll[0] beaconed less than $beacon seconds ago");
            next;
        }

        # Process last position
        #
        # APRS requires a specific coordinate format, see function that
        # builds the APRS packet for more details on packet structure and
        # further reading.
        #
        # ddmm.hhN (i.e. degrees, minutes and hundredths of a minute north)
        #   Example: 4903.50N is 49 degrees 3 minutes 30 seconds north
        # dddmm.hhW (i.e. degrees, minutes and hundredths of a minute west)
        #   Example: 07201.75W is 72 degrees 1 minute 45 seconds west
        my $aprslat;
        my $aprslon;
        if (@lps) {
            # Convert coordinates
            ($aprslat, $aprslon) = convert_coordinates(
                join(' ', $lps[0], $lps[1], $lps[2], $lps[3]),
                join(' ', $lps[4], $lps[5], $lps[6], $lps[7]),
            );
            do_log(3, $func, "posit lat", $aprslat);
            do_log(3, $func, "posit lon", $aprslon);

            # Send to APRS-IS
            do_beacon(@$wxll[0], $aprslat, $aprslon);

        } else {
            # See if we have static position in filter
            unless (defined $calls{@$wxll[0]}{latitude} and defined $calls{@$wxll[0]}{longitude}) {
                do_log(3, $func, "skip", "@$wxll[0] has no posit and no filter posit");
                next;
            }

            # Get lat and long from filter
            ($aprslat, $aprslon) = convert_coordinates(
                $calls{@$wxll[0]}{latitude}, $calls{@$wxll[0]}{longitude}
            );
            do_log(3, $func, "filter lat", $aprslat);
            do_log(3, $func, "filter lon", $aprslon);

            # Send to APRS-IS
            do_beacon(@$wxll[0], $aprslat, $aprslon);
        }
    }
}

sub do_beacon {
    my ($call, $lat, $lon) = @_;

    my $func = "do_beacon";

    if (aprs_write(aprs_packet($call, $lat, $lon))) {

        # Add callsign to last_beacon hash
        $last_beacon{$call} = time();
        do_log(3, $func, 'added to beacon list', $call);
    }    
}

sub aprs_read {
    my $func = "aprs_read";

    my $rd;
    my $call;

    # Read line from APRS-IS
    $rd = $aprsis->getline();
    if ($aprsis->error()) {
        do_log(2, $func, "read fail");
        aprs_close();
        return;
    }

    # We have a line
    if ($rd) {
        do_log(3, $func, 'read line', "$rd");

        # Match originator call sign
        if (($call) = $rd =~ m/^(.*?)>/) {

            # Match call with our call filter
            if (exists $calls{$call}) {

                # Add callsign to heard hash
                $last_heard{$call} = time();
                do_log(3, $func, 'added to heard', "$call");
            }
        }
    }
}

sub aprs_connect {
    my $func = "aprs_connect";

    # Establish new socket connection to server
    $aprsis = IO::Socket::INET->new(
        PeerAddr => $cfg{aprsis}{server},
        PeerPort => $cfg{aprsis}{port},
        Proto    => 'tcp',
        Timeout => 10,
    );

    # Bail if connection attempt failed
    unless ($aprsis) {
        do_log(2, $func, "connect fail", "$cfg{aprsis}{server}");
        return;
    }
    do_log(2, $func, "connect success", "$cfg{aprsis}{server}");


    # Set timeout for read and write
    if ($use_socket_timeout) {
        IO::Socket::Timeout->enable_timeouts_on($aprsis);
        $aprsis->read_timeout(0.5);
        $aprsis->write_timeout(0.5);        
    } else {
        $aprsis->blocking(0);
    }
    
    # Per http://www.aprs-is.net/Connecting.aspx
    #
    # user mycall[-ss] pass passcode[ vers softwarename softwarevers[ UDP udpport][ servercommand]]
    #
    # - mycall-ss=your unique callsign-SSID (-SSID is optional but equates to
    #   zero if omitted, see below). This must be unique throughout APRS and
    #   AX.25. See below for formatting restrictions.
    # - passcode=computed passcode for your callsign. -1 is used for receive-
    #   only. It is the responsibility of each software author to provide the
    #   proper passcode to their individual users on a request basis. This is
    #   to aid in keeping APRS-IS restricted to amateur radio use only.
    # - While the algorithm to generate the passcode is available from some
    #   open-source locations, I will not publish it here. If you are an
    #   Amateur Radio operator writing software for APRS-IS, contact me
    #   directly for the algorithm; otherwise, contact the software author
    #   for your passcode.
    # - softwarename=one word name of the client software. Do not use spaces.
    # - softwarevers=version number of the client software. Do not use spaces.
    # - udpport=UDP port number that the client is listening to
    # - servercommand=any command string (spaces OK) understood by the server.
    #   This will normally be something like 'filter r/33/-96/25' to cause all
    #   packets from stations with 25 km of 33N 96W to be passed to the client.

    my $filter = aprs_filter();
    my $login = "user $cfg{aprsis}{callsign} pass $cfg{aprsis}{password} $filter";
    aprs_write($login);
    return 1;
}

sub aprs_write {
    my ($str) = @_;
    my $func = "aprs_write";

    $aprsis->write("$str\r\n");
    if ($aprsis->error()) {
        do_log(2, $func, "write fail", "$str");
        aprs_close();
        return;
    }
    do_log(2, $func, "write success", "$str");
    return 1;
}

sub aprs_filter {
    my $func = "aprs_filter";

    # See http://www.aprs-is.net/javAPRSFilter.aspx for filter constructs.
    #
    # All "packets" sent to APRS-IS must be in the TNC2 format terminated by a
    # carriage return, line feed sequence. No line may exceed 512 bytes in-
    # cluding the CR/LF sequence. Only verified (valid passcode) clients may 
    # send data to APRS-IS. See the IGate document regarding gating packets to
    # APRS-IS. Packets originating from the client should only have TCPIP* in
    # the path, nothing more or less (AE5PL-TS>APRS,TCPIP*:my packet). For
    # compatibility, the following rules are for any station generating packets:
    #
    # - q constructs should never appear on RF. Only the qAR and qAO constructs
    #   may be generated by a client (IGate) on APRS-IS.
    # - The I construct should never appear on RF. This is an out-dated IGate
    #   construct which should no longer be used.
    # - Except for within 3rd party format gated packets, TCPIP and TCPXX
    #   should not be used on RF.

    my $str = "filter b";
    # Build the APRS-IS filter construct by looping over calls array
    for my $call (keys %calls) {
        $str .= "/$call";
    }
    do_log(3, $func, "", $str);
    return $str;
}

sub aprs_close {
    my $func = "aprs_close";
    do_log(3, $func);

    $aprsis->close();
    undef $aprsis;
}

sub aprs_packet {
    my ($call, $lat, $lon) = @_;

    #
    # See APRS Protocol Reference for details on packet structure
    # http://www.aprs.org/doc/APRS101.PDF 
    #

    my $func = "aprs_packet";
    do_log(3, $func, "call", $call);

    my $packet;

    # Construct packet, start with header
    $packet =  "$call>APRS,TCPIP*:";

    # Add latitude without messaging capability
    $packet .= "!$lat";

    # Add overlay (symbol table)
    $packet .= $calls{$call}{overlay};

    # Add longitude
    $packet .= "$lon";

    # Add symbal (symbol code)
    $packet .= $calls{$call}{overlay};;

    # Add comment
    $packet .= $cfg{aprsis}{comment};

    do_log(3, $func, "packet", $packet);
    return $packet;
}

sub convert_coordinates {
    # a refers to lat
    # b refers to lon
    my ($ain, $bin) = @_;

    my $func = "convert_coordinates";

    my $aout;
    my $bout;

    my @a = split(/\s/, $ain);
    my @b = split(/\s/, $bin);

    # We support 3 formats:
    #
    # N dd mm ss    - Example: N 43 30 15
    # N dd mm.hh    - Example: N 43 30.25
    # -dd.tttttt    - Example: -43.504167 
    if ($a[3] and $b[3]) {
        # Format: N dd mm ss
        $aout = sprintf("%02d%05.2f%s", $a[1], $a[2] + $a[3]/60, $a[0]);
        $bout = sprintf("%03d%05.2f%s", $b[1], $b[2] + $b[3]/60, $b[0]);

    } elsif ($a[2] and $b[2]) {
        # Format: N dd mm.hh
        $aout = sprintf("%02d%05.2f%s", $a[1], $a[2], $a[0]);
        $bout = sprintf("%03d%05.2f%s", $b[1], $b[2], $b[0]);

    } elsif ($a[0] and $b[0]) {
        # Format: -dd.tttttt
        my $as = 'N';
        $as = 'S' if ($a[0] < 0);
        my $bs = 'E';
        $bs = 'W' if ($b[0] < 0);
        $aout = sprintf("%02d%05.2f%s", abs(int $a[0]), 60 * (abs($a[0]) - abs(int $a[0])), $as);
        $bout = sprintf("%03d%05.2f%s", abs(int $b[0]), 60 * (abs($b[0]) - abs(int $b[0])), $bs);
    }
    do_log(3, $func, "latitude", $aout);
    do_log(3, $func, "longitude", $bout);

    return ($aout, $bout);
}

sub replace_path_variables {
    my ($path) = @_;

    my $home = File::HomeDir->my_home;
    $path =~ s!%HOMEPATH%!$home!g;

    return $path;
}

sub load_config {
    my $func = "load_config";
    do_log(2, $func, "file", $cfgfile);

    # Read main configuration file into object
    my $co = Config::Tiny->new;
    $co = Config::Tiny->read($cfgfile);
    unless ($co) {
        do_log(1, $func, "Error", "Cannot open: $cfgfile");
        do_log(1, $func, "Hint", " Run with '-s' to dump sample config");
        exit;
    }

    # Apply config file to %cfg
    config_loop($co, \%cfg);

    # Apply config file to %calls
    calls_loop($co, \%calls);

    # Dump config variables on startup
    config_dump(\%cfg);

    # Dump filter variables on startup
    config_dump(\%calls);
}

sub config_loop {
    my ($srcref, $dstref) = @_;

    # Replace values in %d(e)st(ination) with values from %s(o)rc(e).  This
    # assumes %d(e)st(ination) already has all values defined with defaults.
    for my $k1 (keys %$dstref) {
        for my $k2 (keys %{$dstref->{$k1}}) {
            $dstref->{$k1}->{$k2} = $srcref->{$k1}->{$k2} if ($srcref->{$k1}->{$k2});
        }
    }
}

sub calls_loop {
    my ($srcref, $dstref) = @_;

    # This is specific to loading the callsign filter values from the config
    # file.  A callsign is identified (and distinguished) by 'iscall' being
    # set to 'yes'.
    #
    # In this case the %calls is empty and we populate with all found
    # values.  Loop through %s(o)rc(e) and copy all matching finds into
    # %d(e)st(ination).
    for my $k1 (keys %$srcref) {
        if (defined $srcref->{$k1}->{iscall} and $srcref->{$k1}->{iscall} eq "yes") {
            %{$dstref->{$k1}} = %{$srcref->{$k1}};
        }
    }
}

sub config_dump {
    my ($ref) = @_;
    my $func = "config_dump";

    do_log(2, $func, "", " ");
    for my $k1 (keys %$ref) {
        do_log(2, $func, "", "[$k1]");
        for my $k2 (keys %{$ref->{$k1}}) {
            do_log(2, $func, "", "$k2 = $ref->{$k1}->{$k2}");
        }
        do_log(2, $func, "", " ");
    }
}

sub do_log {
    my ($l, $f, $m, $v) = @_;

    # Log levels
    #
    # 1 - Error
    # 2 - Inform
    # 3 - Debug

    return if ($quiet and $l > 1);
    return if (! $debug and $l > 2);

    print "${f}: " if (defined $f and length $f);
    print "${m}: " if (defined $m and length $m);
    if (defined $v and length $v) {
        $v =~ s/\R//;
        print $v;    
    }
    print "\n";
}

sub usage {
    print "\nUsage: $script{name} [-dhoqsv] [-c configfile] [-i seconds] [-b seconds]\n";
    print "  -b seconds       beacon delay (minimum) in seconds\n";
    print "  -c file          configuration file\n";
    print "  -d               debug information\n";
    print "  -e seconds       expire of log record in seconds\n";
    print "  -h               display usage\n";
    print "  -i seconds       interval in seconds to read log\n";
    print "  -o               one-shot run only once\n";
    print "  -q               quiet, suppress all output\n";
    print "  -s               display default configuration\n";
    print "  -v               display version\n\n";
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
accesslog   = $cfg{wiresx}{accesslog}

# APRS-IS login
[aprsis]
server      = $cfg{aprsis}{server}
port        = $cfg{aprsis}{port}
callsign    = $cfg{aprsis}{callsign}
password    = $cfg{aprsis}{password}
comment     = $cfg{aprsis}{comment}

# Script paramters, command line takes precedence
#
# expire    - how old is too old for wires log entries in seconds
# beacon    - minimum delay between repeated beacons in seconds
# interval  - interval to read the log file in seconds
[script]
expire      = $cfg{script}{expire}
beacon      = $cfg{script}{beacon}
interval    = $cfg{script}{interval}

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
# transmit coordinates, such as the FTM-3200, and are fixed stations.
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
