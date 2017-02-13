# wires-scripts

Scripts to mine information from the [Yaesu](https://www.yaesu.com) [Wires-X](https://www.yaesu.com/jp/en/wires-x/index.php) software and do useful things with it.  These are scripts written in [Perl](https://www.perl.org).  The scripts have been tested on [Windows 7 (32bit)](https://en.wikipedia.org/wiki/Windows_7) using the [Strawberry Perl](http://strawberryperl.com).  To be precise, at the time of writing the installed version of [Strawberry Perl](http://strawberryperl.com) was 5.24.0.1 32bit.

## Getting Started

You will need the have a node running [Yaesu](https://www.yaesu.com) [Wires-X](https://www.yaesu.com/jp/en/wires-x/index.php) software up and running.  You will also need to have login information for the [APRS-IS](http://www.aprs-is.net) to run the `wires2aprs.pl` script and a [FTP](https://en.wikipedia.org/wiki/File_Transfer_Protocol) account somewhere  to use the `wires2html.pl` script.

### Prerequisites

Unfortunately the Microsoft Windows 7 Operating System does not ship with a Perl interpreter.  Download [Strawberry Perl](http://strawberryperl.com) from [http://strawberryperl.com](http://strawberryperl.com) and install.

Once installed, some additional [Perl](https://www.perl.org) modules are needed.  Those are available from [CPAN](http://www.cpan.org).  Many good things can be found there, but let's focus on the task at hand.

Open a Command Prompt (Start Menu -> Search Box -> type 'cmd' folled by the enter key) and enter the following commands.  Wait for each to complete before proceeding with the next command.

```
cpanm install HTTP::Tiny
cpanm install Config::Tiny
cpanm install IO::Socket::Timeout
```

The [Wires-X](https://www.yaesu.com/jp/en/wires-x/index.php) web server is needed for `wires2html.pl` to be able to access information about the node status.  To enable and run the web server follow these steps:

```
Tool(T) > Plugin set
  AddModule
    WiresWeb.dll
Tool(T) > WIRES WebServer
  Access password    :    jones
  Port No.           :    46190
  Remote Control     :    check
```

### Installing

[Clone]() or [download](https://github.com/adilinden/wires-scripts/archive/master.zip) the current version of these scripts and place in a convenient location.  I like to put them into the `Documents` folder.  This should be right alongside (not inside) the [Wires-X](https://www.yaesu.com/jp/en/wires-x/index.php) created `WIRESXA` folder.

In order to run the scripts some configuration files are needed.  The scripts, when executed with the `-s` command line option will dump an example configuration to the screen.  Best is to capture this output to a file and edit each appropriately.  To do this, open a command prompt again, or reuse the command prompt from the earlier [Strawberry Perl](http://strawberryperl.com) installation step.

To get the example configurations for `wires2aprs.pl`:

```
cd %HOMEPATH%\Documents\wires-scripts
wires2aprs.pl > wires2aprs.cfg
```

To get the example configurations for `wires2html.pl`:

```
cd %HOMEPATH%\Documents\wires-scripts
wires2html.pl > wires2html.cfg
```

Now edit these files to your liking.  Having a [FTP](https://en.wikipedia.org/wiki/File_Transfer_Protocol) account somewhere can be tremendously helpful to make good use of `wires2html.pl`.  Having an amateur radio callsign and the appropriate [APRS-IS](http://www.aprs-is.net) password will make `wires2aprs.pl` potentially useful.

## Running the scripts

Open the `wires-scripts` folder in [Windows Explorer](https://en.wikipedia.org/wiki/File_Explorer) and double-click either `wires2aprs.pl` or `wires2html.pl`.  Each script will run and execute in a continuous loop.  The default settings for timing seem to be reasonable to me.  But the timing can be adjusted by specifying command line options or specifying options in the configuration file.  The example configurations created will have all available options contained within.

To have these scripts run when the system starts, add them to the `Startup` folder.

### Configuration

Hopefully the configuration files are self-explanitory.

`wires2aprs.cfg`

```
#
# The sample configuration file for wires2aprs.pl
#

#
# The following path substutions are supported:
#
# %HOMEPATH%    current users home directory
#

# Wires webserver access
[wiresx]
accesslog   = %HOMEPATH%/Documents/WIRESXA/AccHistory/WiresAccess.log

# APRS-IS login
[aprsis]
server      = noam.aprs2.net
port        = 14580
callsign    = N0CALL-YS
password    = 12345
comment     = via Wires-X

# Script paramters, command line takes precedence
#
# expire    - how old is too old for wires log entries in seconds
# beacon    - minimum delay between repeated beacons in seconds
# interval  - interval to read the log file in seconds
[script]
expire      = 180
beacon      = 120
interval    = 60

# Call signs that we filter
#
# See symbol table
# http://wa8lmf.net/miscinfo/APRSsymbolcodes.txt
# http://wa8lmf.net/aprs/APRS_symbols.htm
#
# overlay = which overlay of symbols to use, should be either / or 
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
```

`wires2html.cfg`

```
#
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
host        = 127.0.0.1
port        = 46190
password    = jones
accesslog   = %HOMEPATH%/Documents/WIRESXA/AccHistory/WiresAccess.log

# Node location
#
# For now manually configured and not pulled web interface (yet)
#
[node]
latitude    = 43.806111
longitude   = -81.273889

# FTP target
#
# FTP login information
# 
[ftp]
host        = ftp.qsl.net
username    = n0call
password    = topsecretpassword

# HTML and text templates
#
# To see what each html style produces change the configuration file
# and evaluate the output generated.
#
# trim          number of lines to keep in trim(med) log output
# dir           local directory to look for template files
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
trim        = 6
dir         = templates
liststyle   = table
seperator   = &nbsp;

# Script paramters, command line takes precedence
#
# interval  - interval to read the log file in seconds
[script]
interval    = 60
```

## Built With

* [Perl](https://www.perl.org) - The Perl 5 programming language
* [Strawberry Perl](http://strawberryperl.com) - Perl for Windows
* [HTTP::Tiny](https://metacpan.org/pod/HTTP::Tiny) - HTTP::Tiny - A small, simple, correct HTTP/1.1 client
* [Config::Tiny](https://metacpan.org/pod/Config::Tiny) - Config::Tiny - Read/Write .ini style files with as little code as possible
* [IO::Socket::Timeout](https://metacpan.org/pod/IO::Socket::Timeout) - IO::Socket::Timeout - IO::Socket with read/write timeout

## Contributing

Any suggestions, comments, improvements are welcome.

## Authors

* **Adi Linden** - *Initial work* - [github/adilinden](https://github.com/adilinden)

## License

This project is licensed under the GPLv3 License - see the [GNU General Public License](https://www.gnu.org/licenses/gpl-3.0.en.html) for details
