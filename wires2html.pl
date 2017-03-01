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
#      http://127.0.0.1:46190/?wipassword=jones
#

use strict;
use warnings;

use Time::Local;
use HTTP::Tiny;
use Config::Tiny;
use Getopt::Std;
use File::HomeDir;
use Net::FTP;

##
## Global Variables
##

# Script information
my %script = (
    version     => '1.3-dev',
    wiresx      => '1.120',
    name        => 'wires2html.pl',
    author      => 'Adi Linden <adi@adis.ca>',
    license     => 'GPLv3 <http://www.gnu.org/licenses/>',
    github      => 'https://github.com/adilinden/wires-scripts/',
);

# Template variables kept in hash
#
# nodecall          - Call of node
# nodeid            - User ID of node
# nodeno            - DTMF ID of node
# nodeconnect       - Connected to, or "not connected"
# nodeconnectid     - Connected to, or "--"
# nodeconnectno     - Connected to, or "--"
# nodelist          - List of nodes connected to room
# nodelog_full      - Full nodelog
# nodelog_trim      - Shortened nodelog
#
# userall_full      - All users heard (full)
# userall_trim      - All users heard (trimmed)
# userair_full      - Users heard on air (full)
# userair_trim      - Users heard on air (trimmed)
# usernet_full      - Users heard on net (full)
# usernet_trim      - Users heard on net (trimmed)
#
# mapdatanode       - Node info for map generation
# mapdatauser       - Users heard for map generation
#
# roomname          - Name of room
# roomid            - User ID of room
# roomno            - DTMF ID of room
# roomlist          - List of nodes connected to room
# roomlog_full      - Full roomlog
# roomlog_trim      - Shortened roomlog
#
# now               - current time stamp
# script            - script name
# version           - script version
# author            - script author
# license           - script license
# github            - script repository
#
# apikey            - API key for Google Maps
my %template;

# Saved last connect information
my $lastconnect;

# Configuration (with default values)
my %cfg = (
    wiresx      => {
        host        => '127.0.0.1',
        port        => '46190',
        password    => 'jones',
        accesslog   => "%HOMEPATH%/Documents/WIRESXA/AccHistory/WiresAccess.log",
    },
    node        => {
        latitude    => '43.806111',
        longitude   => '-81.273889',
    },
    ftp         => {
        host        => 'ftp.qsl.net',
        username    => 'n0call',
        password    => 'topsecretpassword',
    },
    html        => {
        trim        => '6',
        dir         => 'templates',
        binary      => 'png gif jpg jpeg pdf js',
        liststyle   => 'table',
        seperator   => '&nbsp;',
    },
    google      => {
        apikey      => 'google-maps-api-key',
    },
    script      => {
        interval    => 60,
    },
);

# Script defaults (overridden by config file and command line args)
my $debug       = "0";
my $quiet       = "0";
my $oneshot     = "0";
my $interval    = "60";
my $cfgfile     = "wires2html.cfg";

# Requried for distance calculation
my $pi = atan2(1,1) * 4;

##
## Main Script
##

# Process command line args
my %args;
unless (getopts('dqoi:c:shv', \%args)) {
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
handle_config();

$interval = $cfg{script}{interval} if (exists $cfg{script}{interval});

$oneshot = 1 if defined $args{o};
$interval = $args{i} if defined $args{i};


# Handle configuration file

# The main loop which runs forever unless 'oneshot' specified
while (1) {

    my $fail = 0;

    # Clear template hash
    %template = (
        nodecall            => "",
        nodeid              => "",
        nodeno              => "",
        nodeconnect         => "",
        nodeconnectid       => "",
        nodeconnectno       => "",
        nodelist            => "",
        nodelog_full        => "",
        nodelog_trim        => "",
        userall_full        => "",
        userall_trim        => "",
        userair_full        => "",
        userair_trim        => "",
        usernet_full        => "",
        usernet_trim        => "",
        mapdatanode         => "",
        mapdatauser         => "",
        roomname            => "",
        roomid              => "",
        roomno              => "",
        roomlist            => "",
        roomlog_full        => "",
        roomlog_trim        => "",
        now                 => scalar localtime(),
        script              => $script{name},
        version             => $script{version},
        author              => $script{author},
        license             => $script{license},
        github              => $script{github},
        apikey              => $cfg{google}{apikey},
   );

    # Handle WiresAccess.log
    $fail++ unless handle_wireslog();

    # Handle nodelog
    $fail++ unless handle_roomlog();

    # Handle nodelog
    $fail++ unless handle_nodelog();

    # That's what we're doing this all for
    bring_it_on() unless ($fail);

    do_log(2, "main", "executed", scalar localtime());

    # Pace ourselves
    if ($oneshot) {
        last;
    }
    else {
        #$interval = 60 if ($interval < 60);
        sleep $interval;
    }
}

##
## Functions
##

sub handle_wireslog {
    my $func = "handle_wireslog";
    do_log(2, $func);

    # File structure
    #
    # User_ID%Radio_ID%Call%Last_Received%Recv_CH%??%Last_Position%??%??%
    #
    # We parse this into a List of Lists (or multi-dimensional array), then
    # sort it in reverse order.  We then parse the list into new List of
    # Lists to seperate nodes into heard via net and heard local while at
    # the same time converting coordinates into a different format to allow
    # building of Google Maps URL lookup.

    # Open, parse, close log
    my @log;
    my $accesslog = replace_path_variables($cfg{wiresx}{accesslog});
    my $fh;
    if (! open($fh, "<:encoding(UTF-8)", $accesslog)) {
        do_log(1, $func, "", "Could not open file '$accesslog' $!");
        return;
    }
    while (<$fh>) {
        push @log, [ split(/%/) ];
    }
    close($fh);

    # Inititalize the log template variables
    my $html = "";
    $html = qq{<div class="userlog">\n} if ($cfg{html}{liststyle} =~ /div|br/);
    $html = qq{<table class="userlog">\n} if ($cfg{html}{liststyle} eq "table");
    $html = qq{<ul class="userlog">\n} if ($cfg{html}{liststyle} eq "ul");
    $template{userall_full} = $html;
    $template{userall_trim} = $html;
    $template{userair_full} = $html;
    $template{userair_trim} = $html;
    $template{usernet_full} = $html;
    $template{usernet_trim} = $html;

    # Reverse sort the array on date field
    @log = sort { $b->[3] cmp $a->[3] } @log;

    # Parse array
    my $i;
    my $ai = 0;
    my $ni = 0;
    for $i (0 .. $#log) {

        my $lat = '';
        my $lon = '';
        my $dist = '';

        if ($log[$i][6]) {
            # Convert coordinates
            ($lat, $lon) = convert_coordinates($log[$i][6]);

            # Get distance (in km)
            if ($lat and $lon) {
                $dist = sprintf("%.2f", distance($cfg{node}{latitude}, $cfg{node}{longitude}, $lat, $lon, "K"));
            }

            # Populate mapdata temlate variable
            $template{mapdatauser} .= "      { ";
            $template{mapdatauser} .= qq{lat: "$lat", };
            $template{mapdatauser} .= qq{lng: "$lon", };
            $template{mapdatauser} .= qq{distance: "$dist", };
            $template{mapdatauser} .= qq{user_id: "$log[$i][0]", };
            $template{mapdatauser} .= qq{call: "$log[$i][2]", };
            $template{mapdatauser} .= qq{heard: "$log[$i][3]", };
            $template{mapdatauser} .= qq{age: "}.heard_to_age($log[$i][3]).qq{", };
            $template{mapdatauser} .= qq{posit: "}.escape_double($log[$i][6]).qq{", };
            $template{mapdatauser} .= qq{channel: "$log[$i][4]", };
            $template{mapdatauser} .= "},\n";
        }

        # Build the user logs
        my $user_row = make_user_row( $log[$i][3], $log[$i][0], $lat, $lon, $dist, $i);
        $template{userall_full} .= $user_row;
        $template{userall_trim} .= $user_row if ($i < $cfg{html}{trim});

        if ($log[$i][4] eq "V-CH") {
            $user_row = make_user_row( $log[$i][3], $log[$i][0], $lat, $lon, $dist, $ai);
            $template{userair_full} .= $user_row;
            $template{userair_trim} .= $user_row if ($ai < $cfg{html}{trim});
            $ai++;
        }

        if ($log[$i][4] eq "Net") {
            $user_row = make_user_row( $log[$i][3], $log[$i][0], $lat, $lon, $dist, $ni);
            $template{usernet_full} .= $user_row;
            $template{usernet_trim} .= $user_row if ($ni < $cfg{html}{trim});
            $ni++;
        }

        do_log(3, $func, "user", "$log[$i][3], $log[$i][0]");
    }

    # Wrap up log template variables
    $html = "";
    $html = "\n</div>" if ($cfg{html}{liststyle} =~ /div|br/);
    $html = "\n</table>" if ($cfg{html}{liststyle} eq "table");
    $html = "\n</ul>" if ($cfg{html}{liststyle} eq "ul");
    $template{userall_full} .= $html;
    $template{userall_trim} .= $html;
    $template{userair_full} .= $html;
    $template{userair_trim} .= $html;
    $template{usernet_full} .= $html;
    $template{usernet_trim} .= $html;

    return 1;
}

sub make_user_row {
    my ($ts, $id, $lat, $lon, $dist, $i) = @_;

    # Build a user log row
    #
    # Last Received
    # User_ID
    # Latitude
    # Longitude
    # Distance
    # Line Number
    my $row;
    my $seperator = qq{<span class="seperator">$cfg{html}{seperator}</span>};
    my $url = qq{<a href="http://maps.google.com/maps?q=$lat,$lon" target="_blank">Map</a>};

    if ($cfg{html}{liststyle} eq "div") {
        # Create row with <div> containers
        $row .= qq{<div class="row">};
        $row .= qq{<div class="heard">$ts</div>};
        $row .= qq{<div class="userid">$id</div>};
        if ($lat and $lon and $dist) {
            $row .= qq{<div class="position">$url</div>};
            $row .= qq{<div class="distance">$dist km</div>};
        }
        $row .= qq{</div>\n};
    }
    elsif ($cfg{html}{liststyle} eq "table") {
        # Create row with html <table>
        $row .= qq{<tr>};
        $row .= qq{<td class="heard">$ts</td>};
        $row .= qq{<td class="userid">$id</td>};
        if ($lat and $lon and $dist) {
            $row .= qq{<td class="position">$url</td>};
            $row .= qq{<td class="distance">$dist km</td>};
        }
        else {
            $row .= qq{<td>&nbsp;</td>};
            $row .= qq{<td>&nbsp;</td>};
        }
        $row .= qq{</tr>\n};
    }
    elsif ($cfg{html}{liststyle} eq "ul") {
        # Create row with html <ul>
        $row .= qq{<li>};
        $row .= qq{<span class="heard">$ts</span>};
        $row .= qq{$seperator<span class="userid">$id</span>};
        if ($lat and $lon and $dist) {
            $row .= qq{$seperator<span class="position">$url</span>};
            $row .= qq{$seperator<span class="distance">$dist km</span>};
        }
        $row .= qq{</li>\n};
    }
    elsif ($cfg{html}{liststyle} eq "br") {
        # If all else fails reate row with html <br>
        $row .= "<br>\n" if ($i > 0);
        $row .= qq{<span class="heard">$ts</span>};
        $row .= qq{$seperator<span class="userid">$id</span>};
        if ($lat and $lon and $dist) {
            $row .= qq{$seperator<span class="position">$url</span>};
            $row .= qq{$seperator<span class="distance">$dist km</span>};
        }
    }
    else {
        # If all else fails reate row with html <br>
        $row .= "<br>\n" if ($i > 0);
        $row .= "$ts - $id";
        $row .= " - $url - $dist" if ($lat and $lon and $dist);
    }
    return $row;
}

sub replace_path_variables {
    my ($path) = @_;

    my $home = File::HomeDir->my_home;
    $path =~ s!%HOMEPATH%!$home!g;

    return $path;
}

sub handle_roomlog {
    my $func = "handle_roomlog";
    do_log(2, $func);

    # Get http content
    my $get = http_get(
        "http://${cfg{wiresx}{host}}:${cfg{wiresx}{port}}/roomlog.html?wipassword=${cfg{wiresx}{password}}");

    if (! $get) {
        do_log(1, $func, "", "HTTP GET failed");
        return;
    }

    if ($get =~ /Round QSO Room Disabled/ ) {
        $template{roomname} = "Room-Disabled";
        $template{roomid} = "Disabled";
        $template{roomno} = "n/a";
        $template{roomlog_full} = "Round QSO Room Disabled";
        $template{roomlog_trim} = "Round QSO Room Disabled";
        do_log(3, $func, "", "Room disabled");
        return 1;
    }

    # Strip unwanted html
    $get =~ s!<b>|</b>|<hr>!!g;

    # Get User ID of room
    my ($name) = $get =~ /ROOM:(.*?),.*?\(/;
    $name = trim($name) if ($name);

    # Get User ID of room
    my ($id) = $get =~ /ROOM:.*?,(.*?)\(/;
    $id = trim($id) if ($id);

    # Get DTMF ID of room
    my ($no) = $get =~ /ROOM:.*?\((.*?)\)/;
    $no = trim($no) if ($no);

    # Get room list
    my ($list) = $get =~ /Connecting.*?<br>(.*?)<br>/;
    $list = trim($list) if ($list);
    $list =~ s/ , /, /g if ($list);

    # Get log
    my ($log) = $get =~ /LOG<br>(.*)/;
    $log =~ s/<br>/\n/g;

    $template{roomname} = $name if ($name);
    $template{roomid} = $id if ($id);
    $template{roomno} = $no if ($no);
    $template{roomlist} = $list if ($list);

    # Inititalize the log template variables
    my $html = "";
    $html = qq{<div class="roomlog">\n} if ($cfg{html}{liststyle} =~ /div|br/);
    $html = qq{<table class="roomlog">\n} if ($cfg{html}{liststyle} eq "table");
    $html = qq{<ul class="roomlog">\n} if ($cfg{html}{liststyle} eq "ul");
    $template{roomlog_full} = $html;
    $template{roomlog_trim} = $html;

    # Reverse the log
    if ($log) {
        my $i = 0;
        for my $line (reverse split(/\n/m, $log)) {
            $template{roomlog_full} .= make_log_row($line, $i);
            $template{roomlog_trim} .= make_log_row($line, $i) if ($i < $cfg{html}{trim});
            $i++;
        }
    }

    # Wrap up log template variables
    $html = "";
    $html = "\n</div>" if ($cfg{html}{liststyle} =~ /div|br/);
    $html = "\n</table>" if ($cfg{html}{liststyle} eq "table");
    $html = "\n</ul>" if ($cfg{html}{liststyle} eq "ul");
    $template{roomlog_full} .= $html;
    $template{roomlog_trim} .= $html;

    do_log(3, $func, "roomname   ", $template{roomname});
    do_log(3, $func, "roomid     ", $template{roomid});
    do_log(3, $func, "roomno     ", $template{roomno});
    do_log(3, $func, "roomlist   ", $template{roomlist});

    return 1;
}

sub handle_nodelog {
    my $func = "handle_nodelog";
    do_log(2, $func);

    # Get http content
    my $get = http_get(
        "http://${cfg{wiresx}{host}}:${cfg{wiresx}{port}}/nodelog.html?wipassword=${cfg{wiresx}{password}}");

    if (! $get) {
        do_log(1, $func, "", "HTTP GET failed");
        return;
    }

    # Strip unwanted html
    $get =~ s!<b>|</b>|<hr>!!g;

    # Get Call of node
    my ($call) = $get =~ /NODE:(.*?),.*?\(/;
    $call = trim($call) if ($call);

    # Get User ID of node
    my ($id) = $get =~ /NODE:.*?,(.*?)\(/;
    $id = trim($id) if ($id);

    # Get DTMF ID of node
    my ($no) = $get =~ /NODE:.*?\((.*?)\)/;
    $no = trim($no) if ($no);

    # Get "Connect to"
    my ($isconnect) = $get =~ /Connect to(.*?)<br>/;
    $isconnect = trim($isconnect) if ($isconnect);

    # Get node list
    my ($list) = $get =~ /Node list<br>(.*?)<br>/;
    $list = trim($list) if ($list);
    $list =~ s/ , /, /g if ($list);

    # Get last "Connected to" from log
    my ($wasconnect) = $get =~ /.*Connected to(.*?)\./;
    $wasconnect = trim($wasconnect) if ($wasconnect);

    # Get log
    my ($log) = $get =~ /LOG<br>(.*)/;
    $log =~ s/<br>/\n/g;        # replace line break with LF
    $log =~ s/.*?Browser.*?\n//g;   # remove browser lines

    # Here is a curiousity of the Wires-X software.  The "Connect to"
    # field in the nodelog shows the current room or node connected to,
    # just as one would expect.  However, if "Return to room" has been
    # configured, the upon a "Return to room" connection this field does
    # not get populated.  Although the node is in fact connected to the
    # room and has a valid node list.  
    #
    # To workaround we use the last available "Connected to" line from
    # the log if the "Connect to" is empty but the node list is populated.
    # This should not present a problem as we cannot connect to an empty
    # room (of we are the only) connection we still show in the node list,
    # so node list would not be empty.
    #
    # A further issues was observed when the room connection persists for
    # long periods of time.  The "Connected to" line will eventually be
    # trimmed from the log in which case we still have a valid node list
    # but no longer any indication of what we might be connected to.  Since
    # this script now runs continuosly, instead of being started for each
    # individual run, we can save the connect information as long as this
    # script remains running.
    #
    my $connect;
    if ($isconnect) {
        $connect = $isconnect;
    }
    elsif ($wasconnect and $list) {
        $connect = $wasconnect;
        # Save connected node for later
        $lastconnect = $wasconnect;
    }
    elsif ($lastconnect and $list) {
        $connect = $lastconnect;
    }

    if ($connect) {
        $template{nodelist} = $list if ($list);
        $template{nodeconnect} = $connect;
        ($template{nodeconnectid}) = $connect =~ /(.*?)\(.*?\)/;
        ($template{nodeconnectno}) = $connect =~ /.*?\((.*?)\)/;
    }
    else {
        $template{nodeconnect} = "not connected";
        $template{nodeconnectid} = "--";
        $template{nodeconnectno} = "--";
    }

    $template{nodecall} = $call if ($call);
    $template{nodeid} = $id if ($id);
    $template{nodeno} = $no if ($no);

    # Inititalize the log template variables
    my $html = "";
    $html = qq{<div class="nodelog">\n} if ($cfg{html}{liststyle} =~ /div|br/);
    $html = qq{<table class="nodelog">\n} if ($cfg{html}{liststyle} eq "table");
    $html = qq{<ul class="nodelog">\n} if ($cfg{html}{liststyle} eq "ul");
    $template{nodelog_full} = $html;
    $template{nodelog_trim} = $html;

    # Reverse the log
    if ($log) {
        my $i = 0;
        for my $line (reverse split(/\n/m, $log)) {
            $template{nodelog_full} .= make_log_row($line, $i);
            $template{nodelog_trim} .= make_log_row($line, $i) if ($i < $cfg{html}{trim});
            $i++;
        }
    }

    # Wrap up log template variables
    $html = "";
    $html = "\n</div>" if ($cfg{html}{liststyle} =~ /div|br/);
    $html = "\n</table>" if ($cfg{html}{liststyle} eq "table");
    $html = "\n</ul>" if ($cfg{html}{liststyle} eq "ul");
    $template{nodelog_full} .= $html;
    $template{nodelog_trim} .= $html;

    # Populate mapdata temlate variable
    $template{mapdatanode}  = "{ ";
    $template{mapdatanode} .= qq{lat: "$cfg{node}{latitude}", };
    $template{mapdatanode} .= qq{lng: "$cfg{node}{longitude}", };
    $template{mapdatanode} .= qq{user_id: "$template{nodeid}", };
    $template{mapdatanode} .= qq{call: "$template{nodecall}", };
    $template{mapdatanode} .= qq{number: "$template{nodeno}", };
    $template{mapdatanode} .= qq{age: 1, };
    $template{mapdatanode} .= "}";

    do_log(3, $func, "isconnect  ", $isconnect);
    do_log(3, $func, "wasconnect ", $wasconnect);
    do_log(3, $func, "list       ", $list);

    do_log(3, $func, "nodecall   ", $template{nodecall});
    do_log(3, $func, "nodeid     ", $template{nodeid});
    do_log(3, $func, "nodeno     ", $template{nodeno});
    do_log(3, $func, "nodeconnect", $template{nodeconnect});
    do_log(3, $func, "nodeconnectid", $template{nodeconnectid});
    do_log(3, $func, "nodeconnectno", $template{nodeconnectno});
    do_log(3, $func, "nodelist   ", $template{nodelist});

    return 1;
}

sub make_log_row {
    my ($line, $i) = @_;

    # Each line is a timestamp followed by log string.  Let's hit the
    # timestamp with some styling possibilities.
    #
    # Example line:
    #
    # 2017/02/12 19:22:04  VA3EOD-RPT(18138) IN. 8 Nodes.
    my ($ts, $str) = $line =~ m!^(\d+/\d+/\d+ \d+:\d+:\d+)\s+(.*)$!;
    return " " unless ($ts and $str);

    my $row;
    my $seperator = qq{<span class="seperator">$cfg{html}{seperator}</span>};

    if ($cfg{html}{liststyle} eq "div") {
        # Create row with <div> containers
        $row .= qq{<div class="row">};
        $row .= qq{<div class="when">$ts</div>};
        $row .= qq{<div class="log">$str</div>};
        $row .= qq{</div>\n};
    }
    elsif ($cfg{html}{liststyle} eq "table") {
        # Create row with html <table>
        $row .= qq{<tr>};
        $row .= qq{<td class="when">$ts</td>};
        $row .= qq{<td class="log">$str</td>};
        $row .= qq{</tr>\n};
    }
    elsif ($cfg{html}{liststyle} eq "ul") {
        # Create row with html <ul>
        $row .= qq{<li>};
        $row .= qq{<span class="when">$ts</span>};
        $row .= qq{$seperator<span class="log">$str</span>};
        $row .= qq{</li>\n};
    }
    elsif ($cfg{html}{liststyle} eq "br") {
        # If all else fails reate row with html <br>
        $row .= "<br>\n" if ($i > 0);
        $row .= qq{<span class="when">$ts</span>};
        $row .= qq{$seperator<span class="log">$str</span>};
    }
    else {
        # If all else fails reate row with html <br>
        $row .= "<br>\n" if ($i > 0);
        $row .= "$ts $str";
    }
    return $row;
}

sub bring_it_on {
    # - Connect to FTP server
    # - Change to target directory
    # - Read templates dir
    #   - Read file into var
    #     - Replace template variables
    #   - Close file
    #   - FTP put
    #           $ftp->put($fh, "$file");
    # - Close FTP
    my $func = "bring_it_on";
    do_log(2, $func);

    my $ftpdir = $template{nodeno};
    unless ($ftpdir) {
        do_log(1, $func, "error", "Missing nodeno");
        return;
    }

    # Connect to FTP
    my $ftp = ftp_open();
    return unless ($ftp);

    # Read the directory
    read_dir($ftp, $cfg{html}{dir}, $ftpdir);

    # Close FTP
    ftp_close($ftp);
}

sub read_dir {
    my ($ftp, $ldir, $rdir) = @_;

    my $func = "read_dir";
    do_log(2, $func, '', "local: $ldir, remote: $rdir");

    # Notes:
    #
    #   - The local directory $ldir is a path that can be several
    #     several directories deep
    #   - The remote directory $rdir is a single directory that we
    #     descend into

    # (Create) and change dir on FTP server
    return unless ftp_dir($ftp, $rdir);

    # Handle local directory
    my $dh;
    if (opendir($dh, $ldir)) {
        while (my $file = readdir $dh) {

            # Skip dot files
            next if ($file =~ m/^\./);

            # Recurse into directories
            if (-d "$ldir/$file") {
                read_dir($ftp, "$ldir/$file", $file);
                next;
            }

            # Skip unless a plain file
            next unless (-f "$ldir/$file");

            # Process file
            my $gut;

            # Regex to test file extensions
            (my $ext = trim($cfg{html}{binary})) =~ s/(\s+)/|/g;
            if ($file =~ m/^.*\.($ext)$/) {
                # Is binary file
                read_binary("$ldir/$file", \$gut);            
                $ftp->binary();
            } else {
                # Is text file
                read_text("$ldir/$file", \$gut);
                $ftp->ascii();
            }

            # Send file to FTP server
            ftp_put($ftp, "$file", \$gut);
        }

        # Done with local directory
        closedir($dh);
    } else {
        do_log(1, $func, "opendir", "Could not open '$ldir' $!");
    }

    # Change dir on the FTP server (go up)
    $ftp->cdup();
}

sub read_text {
    my ($file, $gutref) = @_;

    my $func = "read_text";
    do_log(2, $func, '', $file);

    my $fh;
    if (! open($fh, "<", $file)) {
        do_log(1, $func, "open", "Could not open file '$file' $!");
        return;
    }

    # Build regex match from template hash keys
    my $search_for = join '|', map quotemeta, keys %template;

    # Read file into variable and replace template variables
    while (<$fh>) {
        s/\{\{($search_for)\}\}/$template{$1}/g;
        $$gutref .= $_;
    }

    close($fh);
    return 1;
}

sub read_binary {
    my ($file, $gutref) = @_;

    my $func = "read_binary";
    do_log(2, $func, '', $file);

    my $fh;
    if (! open($fh, "<", $file)) {
        do_log(1, $func, "open", "Could not open file '$file' $!");
        return;
    }

    # Read file into variable and replace template variables
    while (<$fh>) {
        $$gutref .= $_;
    }

    close($fh);
    return 1;
}

sub ftp_open {
    my $func = "ftp_open";
    do_log(2, $func, "hostname", $cfg{ftp}{host});
    do_log(3, $func, "username", $cfg{ftp}{username});

    # Connect to FTP server
    my $ftp = Net::FTP->new($cfg{ftp}{host}, timeout => 5);
    if (! $ftp) {
        do_log(1, $func, "Can't open $cfg{ftp}{host}");
        return;
    }
    if (! $ftp->login($cfg{ftp}{username}, $cfg{ftp}{password})){
        do_log(1, $func, "Can't login as $cfg{ftp}{username}");
        return;
    }
    return $ftp;
}

sub ftp_dir {
    # Change directory and create if needed
    my ($ftp, $dir) = @_;

    my $func = "ftp_dir";
    do_log(2, $func, "cd to", $dir);

    # Change directory (return on success)
    return 1 if ($ftp->cwd($dir));

    # Create directory
    $ftp->mkdir($dir);

    # Change directory (return on success)
    return 1 if ($ftp->cwd($dir));

    # Failed...
    do_log(1, $func, "error", "Failed to change to '$dir'");
    return;
}

sub ftp_put {
    my ($ftp, $file, $gutref) = @_;

    my $func = "ftp_put";
    do_log(2, $func, '', $file);

    # Open file handle for variable and write to FTP server
    my $fh;
    if (! open($fh, "<", $gutref)) {
        do_log(1, $func, "open", "Could not open filehandle for \$gut $!");
        return;
    }
    $ftp->put($fh, $file);
    close($fh);
}

sub ftp_close {
    my ($ftp) = @_;

    my $func = "ftp_close";
    do_log(3, $func);

    $ftp->close();
}

sub http_get {
    my ($url) = @_;
    do_log(3, "http_get", "url", $url);

    my $http = HTTP::Tiny->new(timeout => 2);
    my $r = $http->get($url);
    if ($r->{success}) {
        return $r->{content};
    }
    return;
}

sub heard_to_age {
    my ($time) = @_;

    my $func = "heard_to_age";
    do_log(3, $func, "in time", $time);

    # Parse date
    # Example: 2017/01/07 21:26:05
    my @cap = $time =~ m!^(\d+)/(\d+)/(\d+) (\d+):(\d+):(\d+)$!;
	my $age = time() - timelocal($cap[5], $cap[4], $cap[3], $cap[2], $cap[1] - 1, $cap[0]);

    do_log(3, $func, "out age", "$age");
    return $age;
}

sub convert_coordinates {
    my ($coord) = @_;

    my $func = "convert_coordinates";
    do_log(3, $func, "in coord", $coord);

    # Capture coordinates into an array
    #
    # Two possible formats:
    #
    #    N:39 08' 34" / W:077 10' 03"
    #    Lat:N:45 28' 57" / Lon:W:075 31' 41" / R:001km /
    #
    # Latitude:
    # $cap[0] :     N|S
    # $cap[1] :     degree
    # $cap[2] :     minute
    # $cap[3] :     second
    #
    # Longitude:
    # $cap[4] :     E|W
    # $cap[5] :     degree
    # $cap[6] :     minute
    # $cap[7] :     second
    my @cap = $coord =~ m!^([NS]):(\d+) (\d+)\' (\d+)" / ([EW]):(\d+) (\d+)\' (\d+)"$!;

    # Try the alternate fomrat seen in log
    unless (@cap) {
        @cap = $coord =~ m!^Lat:([NS]):(\d+) (\d+)\' (\d+)" / Lon:([EW]):(\d+) (\d+)\' (\d+)".*?$!;
    }

    my $lat = '';
    my $lon = '';
    if (@cap) {
        # Calculate decimal degrees from degree, minute, second
        $lat = $cap[1] + ($cap[2] + $cap[3] / 60) / 60;
        $lon = $cap[5] + ($cap[6] + $cap[7] / 60) / 60;

        # Add N, S, E, W
        #$lat = sprintf("%.6f".$cap[0], $lat);
        #$lon = sprintf("%.6f".$cap[4], $lon);

        # Add +/-
        $lat = 0 - $lat if ($cap[0] eq "S");
        $lon = 0 - $lon if ($cap[4] eq "W");
        $lat = sprintf("%.6f", $lat);
        $lon = sprintf("%.6f", $lon);

        do_log(3, $func, "lat/long", "$lat/$lon");
    }
    return($lat, $lon);
}

sub handle_config {
    my $func = "handle_config";
    do_log(2, $func, "file", $cfgfile);

    # Read main configuration file
    my $co = Config::Tiny->new;
    $co = Config::Tiny->read($cfgfile);
    unless ($co) {
        do_log(1, $func, "Error", "Cannot open: $cfgfile");
        do_log(1, $func, "Hint", " Run with '-s' to dump sample config");
        exit;
    }

    # Apply config file values
    config_loop($co, \%cfg);

    # Dump config variables on startup
    config_dump(\%cfg);
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

sub escape_double {
    my $s = shift;
    $s =~ s/(["])/\\$1/g;
    return $s;
}

sub trim {
    my $s = shift;
    $s =~ s/^\s+|\s+$//g;
    return $s;
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

    print "${f}: " if defined $f and length $f;
    print "${m}: " if defined $m and length $m;
    print "${v} " if defined $v and length $v;
    print "\n";
}

sub usage {
    print "\nUsage: $script{version} [-dhoqsv] [-c configfile] [-i seconds]\n";
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
# The sample configuration file for wires2html.pl
#

#
# Enabling the Wires-X web interface:
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
#      http://127.0.0.1:46190/?wipassword=jones
#
# The following path substutions are supported:
#
# %HOMEPATH%    current users home directory
#

# Wires webserver access
[wiresx]
host        = $cfg{wiresx}{host}
port        = $cfg{wiresx}{port}
password    = $cfg{wiresx}{password}
accesslog   = $cfg{wiresx}{accesslog}

# Node location
#
# For now manually configured and not pulled web interface (yet)
#
[node]
latitude    = $cfg{node}{latitude}
longitude   = $cfg{node}{longitude}

# FTP target
#
# FTP login information
# 
[ftp]
host        = $cfg{ftp}{host}
username    = $cfg{ftp}{username}
password    = $cfg{ftp}{password}

# HTML and text templates
#
# To see what each html style produces change the configuration file
# and evaluate the output generated.
#
# trim          number of lines to keep in trim(med) log output
# dir           local directory to look for template files
# binary        file extensions exempt from substitutions
# liststyle     how to construct the lists, valid values:
#       br      list wrappen in <div> using <br> with each line
#       div     table styled using <div> containers
#       simple  simple line breaks using <br> html tags
#       table   table styled using <table> tags
#       ul      simple unordered list using <ul> and <li> tags
# seperator     string used as seperator between elements when using
#               list styles 'br' or 'ul'
#
[html]
trim        = $cfg{html}{trim}
dir         = $cfg{html}{dir}
binary      = $cfg{html}{binary}
liststyle   = $cfg{html}{liststyle}
seperator   = $cfg{html}{seperator}

# API Key for Google Maps
#
# See https://developers.google.com/maps/documentation/javascript/get-api-key
#
[google]
apikey      = $cfg{google}{apikey}

# Script paramters, command line takes precedence
#
# interval  - interval to read the log file in seconds
[script]
interval    = $cfg{script}{interval}
};
    exit;
}

##
## Function to calculate distance
## http://www.geodatasource.com/developers/perl
## The sample code is licensed under LGPLv3
##

#
#  This routine calculates the distance between two points (given the
#  latitude/longitude of those points). It is being used to calculate
#  the distance between two locations using GeoDataSource(TM) products
#
#  Definitions:
#    South latitudes are negative, east longitudes are positive
#
#  Passed to function:
#    lat1, lon1 = Latitude and Longitude of point 1 (in decimal degrees)
#    lat2, lon2 = Latitude and Longitude of point 2 (in decimal degrees)
#    unit = the unit you desire for results
#           where: 'M' is statute miles (default)
#                  'K' is kilometers
#                  'N' is nautical miles
#
#  Worldwide cities and other features databases with latitude longitude
#  are available at http://www.geodatasource.com
#
#  For enquiries, please contact sales@geodatasource.com
#
#  Official Web site: http://www.geodatasource.com
#
#            GeoDataSource.com (C) All Rights Reserved 2015

#
# Example
#
# print distance(32.9697, -96.80322, 29.46786, -98.53506, "M") . " Miles\n";
#

#my $pi = atan2(1,1) * 4;

sub distance {
    my ($lat1, $lon1, $lat2, $lon2, $unit) = @_;
    my $theta = $lon1 - $lon2;
    my $dist = sin(deg2rad($lat1)) * sin(deg2rad($lat2)) + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * cos(deg2rad($theta));
    $dist  = acos($dist);
    $dist = rad2deg($dist);
    $dist = $dist * 60 * 1.1515;
    if ($unit eq "K") {
        $dist = $dist * 1.609344;
    } elsif ($unit eq "N") {
        $dist = $dist * 0.8684;
    }
    return ($dist);
}

#  This function get the arccos function using arctan function
sub acos {
    my ($rad) = @_;
    my $ret = atan2(sqrt(1 - $rad**2), $rad);
    return $ret;
}

#  This function converts decimal degrees to radians
sub deg2rad {
    my ($deg) = @_;
    return ($deg * $pi / 180);
}

#  This function converts radians to decimal degrees
sub rad2deg {
    my ($rad) = @_;
    return ($rad * 180 / $pi);
}

# End