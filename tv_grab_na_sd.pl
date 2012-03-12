#!/usr/bin/perl -w
# Robert Kulagowski

use strict;
use Getopt::Long;
use WWW::Mechanize;
use POSIX  qw(strftime);

my $version = "0.01";
my $date    = "2012-03-12";

my ( @deviceid, @deviceip, @device_hwtype, @qam, @program, @hdhr_callsign );
my ( @lineupinformation, @SD_callsign, @xmlid, @schedule_url, @data );
my $i              = 0;
my $channel_number = 0;
my $lineupid       = "";
my $devtype        = "";
my $username;
my $password;
my $help;
my $zipcode = "0";
my $response;
my $debugenabled=0;
my $fh;

GetOptions(
    'debug'       => \$debugenabled,
    'zipcode=s'   => \$zipcode,
    'lineupid=s'  => \$lineupid,
    'devtype=s'   => \$devtype,
    'username=s'  => \$username,
    'password=s'  => \$password,
    'help|?'      => \$help
);

# Extract the list of known device types
my %device_type_hash = (
    'A' => 'Cable A lineup',
    'B' => 'Cable B lineup',
    'C' => 'Reserved',
    'D' => 'Cable (Rebuild)',
    'E' => 'Reserved',
    'F' => 'Cable-ready TV sets (Rebuild)',
    'G' => 'Non-addressable converters and cable-ready sets',
    'H' => 'Hamlin converter',
    'I' => 'Jerrold impulse converter',
    'J' => 'Jerrold converter',
    'K' => 'Reserved',
    'L' => 'Digital (Rebuild)',
    'M' => 'Reserved',
    'N' => 'Pioneer converter',
    'O' => 'Oak converter',
    'P' => 'Reserved',
    'Q' => 'Reserved',
    'R' => 'Cable-ready TV sets (non-rebuild)',
    'S' => 'Reserved',
    'T' => 'Tocom converter',
    'U' => 'Cable-ready TV sets with Cable A',
    'V' => 'Cable-ready TV sets with Cable B',
    'W' => 'Scientific-Atlanta converter',
    'X' => 'Digital',
    'Y' => 'Reserved',
    'Z' => 'Zenith converter',
    ''  => 'Cable',
);

############## Start of main program

if ($help) {
    print <<EOF;
tv_grab_na_sd.pl v$version $date
Usage: tv_grab_na_sd.pl [switches]

This script supports the following command line arguments.

--debug                    Enable debug mode. Prints additional information
                           to assist in troubleshooting any issues.
                           
--zipcode                  When grabbing the channel list from Schedules
                           Direct, you can supply your 5-digit zip code or
                           6-character postal code to get a list of cable TV
                           providers in your area, otherwise you'll be
                           prompted.  If you're specifying a Canadian postal
                           code, then use six consecutive characters, no
                           embedded spaces.

--lineupid                 Your headend identifier.
--devtype                  Headend device type. Defaults to "blank", the
                           traditional analog lineup.

--username                 Login credentials.
--password                 Login credentials.

--help                     This screen.

Bug reports to rkulagow\@schedulesdirect.org  Include the .conf file and the
complete output when the script is run with --debug

EOF
    exit;
}

# Yes, goto sometimes considered evil. But not always.

if ($username eq "")
{
  print "Enter your Schedules Direct username: ";
  chomp ($username = <STDIN>);
}

if ($password eq "")
{
  print "Enter password: ";
  chomp ($password = <STDIN>);
}

START:
if ( $zipcode eq "0" ) {
    print "\nPlease enter your zip code / postal code to download lineups:\n";
    chomp( $zipcode = <STDIN> );
}

$zipcode = uc($zipcode);

unless ( $zipcode =~ /^\d{5}$/ or $zipcode =~ /^[A-Z0-9]{6}$/ ) {
    print
"Invalid zip code specified. Must be 5 digits for U.S., 6 characters for Canada.\n";
    $zipcode = "0";
    goto START;
}

my $m = WWW::Mechanize->new();
$m->credentials($username, $password);

$m->get("http://rkulagow.schedulesdirect.org/li.php");
$m->save_content("randhash.txt");
open( $fh, "<", "randhash.txt" )
  or die "Fatal error: could not open randhash.txt: $!\n";
my $randhash = <$fh>;
close $fh;

chomp ($randhash);

if ($randhash eq "Wrong Credentials!")
{
  print "Incorrect username or password, exiting.\n";
  exit(1);
}

$m->get(
"http://rkulagow.schedulesdirect.org/process.php?command=get&p1=headend&p2=$zipcode"
);
$m->save_content("available_headends.txt");

open( $fh, "<", "available_headends.txt" )
  or die "Fatal error: could not open available.txt: $!\n";
my $row = 0;
my @he;
while ( my $line = <$fh> ) {
    chomp($line);

    # Skip the ones that aren't cable lineups.
    next if ( $line =~ /Name:Antenna/ );
    my @vals = split /\|/, $line;
    $he[$row]->{'headend'}  = shift @vals;
    $he[$row]->{'name'}     = shift @vals;
    $he[$row]->{'location'} = shift @vals;
    $he[$row]->{'url'}      = shift @vals;
    $row++;
}    #end of the while loop
$row--;
close $fh;

print "\n";

if ( $lineupid eq
    "" )    # if the lineupid wasn't passed as a parameter, ask the user
{
    for my $j ( 0 .. $row ) {
        print
"$j. $he[$j]->{'name'}, $he[$j]->{'location'} ($he[$j]->{'headend'})\n";
    }
    print "\nEnter the number of your lineup, 'Q' to exit, 'A' to try again: ";

    chomp( $response = <STDIN> );
    $response = uc($response);

    if ( $response eq "Q" ) {
        exit;
    }

    if ( $response eq "A" ) {
        $zipcode = "0";
        goto START;
    }

    $response *= 1;    # Numerify it.

    if ( $response < 0 or $response > $row ) {
        print "Invalid choice.\n";
        $zipcode = "0";
        goto START;
    }

    $lineupid = $he[$response]->{'headend'};
}
else # we received a lineupid
{
  for my $elem (0 .. $row)
  {
    if ($he[$elem]->{'headend'} eq $lineupid)
    {
      $response = $elem;
    }
  }
}

print "\nDownloading lineup information.\n";

$m->get( $he[$response]->{'url'} );
$m->save_content("$lineupid.txt.gz");

print "Unzipping file.\n\n";
system("gunzip --force $lineupid.txt.gz");

open( $fh, "<", "$lineupid.txt" )
  or die "Fatal error: could not open $lineupid.txt: $!\n";

my @headend_lineup = <$fh>;
chomp(@headend_lineup);
close $fh;

$row = 0;
my $line = -1;    # Deliberately start less than 0 to catch the first entry.
my @device_type;

foreach my $elem (@headend_lineup) {
    $line++;
    next unless $elem =~ /^Name/;
    $elem =~ /devicetype:(.?)/;
    $device_type[$row]->{'type'} = $1;    # The device type
    $device_type[$row]->{'linenumber'} =
      $line;    # store the line number as the second element.

    if ( $device_type[$row]->{'type'} eq "|" ) {
        $device_type[$row]->{'type'} = "";
    }
    $row++;
}
$row--;

if ( $devtype eq "" ) # User didn't pass the device type as a parameter, so ask.
{
    if ( $row > 0 )    # More than one device type was found.
    {
        print "The following device types are available on this headend:\n";
        for my $j ( 0 .. $row ) {
            print "$j. $device_type_hash{$device_type[$j]->{'type'}} ($device_type[$j]->{'type'})\n";
        }

        print "Enter the number of the lineup you are scanning: ";
        chomp( $response = <STDIN> );
        $response = uc($response);

        if ( $response eq "Q" ) {
            exit;
        }

        $response *= 1;    # Numerify it.

        if ( $response < 0 or $response > $row ) {
            print "Invalid choice.\n";
            $zipcode = "0";
            goto START;
        }
    }
    else {
        $response = 0;
    }
}
else #devtype was passed
{
  for my $elem (0 .. $row)
  {
    if ($device_type[$elem]->{'type'} eq $devtype)
    {
      $response = $elem;
    }
  }
}

# If the user selects the last entry, then create a fake so that we look
# through the end of the file.
if ( $response == $row ) {
    $device_type[ $row + 1 ]->{'linenumber'} = scalar(@headend_lineup);
}

# Start at the first line after the "Name" line, end one line before the next "Name" line.

print "Downloading schedules.\n";

for my $elem ( $device_type[$response]->{'linenumber'} +
    1 .. ( $device_type[ $response + 1 ]->{'linenumber'} ) -
    1 )
{
    my $line = $headend_lineup[$elem];
    $line =~ /^channel:(\d+) callsign:(\w+) stationid:(\d+) (.*+)$/;
    $SD_callsign[$elem] = $2;
    $xmlid[$elem]       = $3;
    $schedule_url[$elem]= $4;
    $m->get($schedule_url[$elem] . "&rand=" . $randhash);
    $m->save_content("$xmlid[$elem]_sched.txt.gz");
}

print "\nDone.\n";

exit(0);
