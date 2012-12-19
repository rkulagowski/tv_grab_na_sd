#!/usr/bin/perl -w
# Robert Kulagowski
# sudo apt-get install libwww-mechanize-perl libjson-perl libjson-xs-perl

use strict;
use Getopt::Long;
use WWW::Mechanize;
use POSIX qw(strftime);
use JSON;
use Data::Dumper;

my $version = "0.10";
my $date    = "2012-12-18";

my @lineupdata;
my $i = 0;
my %headendURL;
my $username = "";
my $password = "";
my $help;
my $zipcode = "0";
my $randhash;
my $response;
my $debugenabled = 0;
my $configure    = 0;
my $fn;
my $fh;
my $row = 0;
my @he;
my $m = WWW::Mechanize->new();
my $url;
my $get_all_lineups_in_zip = 0;
my %req;

# API must match server version.
my $api = 20121217;

# If we specify a randhash, we only get back the configured lineups in our
# account, otherwise you get everything in your postal code.

# The root of the download location for testing purposes.

my $baseurl = "http://ec2-23-21-174-111.compute-1.amazonaws.com";

GetOptions(
    'debug'      => \$debugenabled,
    'configure'  => \$configure,
    'zipcode=s'  => \$zipcode,
    'username=s' => \$username,
    'password=s' => \$password,
    'help|?'     => \$help
);

if ($help)
{
    print <<EOF;
tv_grab_na_sd.pl v$version $date
Usage: tv_grab_na_sd.pl [switches]

This script supports the following command line arguments.

--configure     Re-runs the configure sequence and ignores any existing
                tv_grab_na_sd.conf file. You may still pass login
                credentials and zipcode if you want to bypass interactive
                configuration.

--debug         Enable debug mode. Prints additional information
                to assist in troubleshooting any issues.

--username      Login credentials.
--password      Login credentials. NOTE: These will be visible in "ps".

--zipcode       When obtaining the channel list from Schedules Direct
                you can supply your 5-digit zip code or
                6-character postal code to get a list of cable TV
                providers in your area, otherwise you'll be
                prompted.  If you're specifying a Canadian postal
                code, then use six consecutive characters, no
                embedded spaces.

--help          This screen.

Bug reports to grabber\@schedulesdirect.org  Include the .conf file and the
complete output when the script is run with --debug

EOF
    exit;
}

if ( -e "tv_grab_na_sd.conf" && $configure == 0 )
{
    open( $fh, "<", "tv_grab_na_sd.conf" );
    @lineupdata = <$fh>;
    chomp(@lineupdata);
    close($fh);
    foreach (@lineupdata)
    {
        if ( $_ =~ /^username:(.*) password:(.*) zipcode:(.{5,6})/ )
        {
            $username = $1;
            $password = $2;
            $zipcode  = $3;
        }
        if ( $_ =~ /^headend:(\S+) (.+)/ )
        {
            $headendURL{$1} = $2;
        }
    }

    # Password is the only field to leave blank in the config file if you're
    # paranoid about that sort of thing.
    if ( $password eq "" )
    {
        print "No password specified in .conf file.\nEnter password: ";
        chomp( $password = <STDIN> );
    }

    $randhash = &login_to_sd( $username, $password );

    &print_status($randhash);

    print "\nDownloading.\n";

    &get_headends();
    &download_schedules($randhash);

    print "Done.\n";
    exit(0);
}

# No configuration file, so we have to manually go through setup.
if ( $username eq "" )
{
    print "Enter your Schedules Direct username: ";
    chomp( $username = <STDIN> );
}

if ( $password eq "" )
{
    print "Enter password: ";
    chomp( $password = <STDIN> );
}

while (1)
{
    if ( $zipcode =~ /^\d{5}$/ or $zipcode =~ /^[A-Z0-9]{6}$/ )
    {
        last;
    }
    print
"Please enter your zip code / postal code to download headends for your area.\n";
    print "5 digits for U.S., 6 characters for Canada: ";
    chomp( $zipcode = <STDIN> );
    $zipcode = uc($zipcode);
}

$randhash = &login_to_sd( $username, $password );
&print_status($randhash);

# If the randhash is sent, then we're going to get only the headends that the
# user has already configured.  No randhash means all possible headends in
# this zip / postal code.

if ( $get_all_lineups_in_zip == 0 )
{
    $response = &get_headends( "none", $zipcode );
}
else
{
    $response = &get_headends( $randhash, $zipcode );
}

open( $fh, "<", "available_headends.json.txt" )
  or die "Fatal error: could not open available_headends.json.txt: $!\n";
while ( my $line = <$fh> )
{
    my $he_hash = decode_json($line);
    $he[$row]->{'headend'}  = $he_hash->{headend};
    $he[$row]->{'name'}     = $he_hash->{Name};
    $he[$row]->{'location'} = $he_hash->{Location};
    $row++;
}    #end of the while loop
$row--;
close $fh;

while (1)
{
    print "Queued\n";
    for my $j ( 0 .. $row )
    {
        if ( defined $headendURL{ $he[$j]->{'headend'} } )
        {
            print "*";
        }
        print
"\t$j. $he[$j]->{'name'}, $he[$j]->{'location'} ($he[$j]->{'headend'})\n";
    }
    print
"\nEnter the number of the lineup you want to add / remove, 'D' for Done, 'Q' to exit: ";

    chomp( $response = <STDIN> );
    $response = uc($response);

    if ( $response eq "Q" )
    {
        exit(0);
    }

    if ( $response eq "D" )
    {
        last;
    }

    $a = $response * 1;    # Numerify it.

    if ( $a < 0 or $a > $row )
    {
        print "Invalid choice.\n";
        next;
    }

    if ( defined $headendURL{ $he[$a]->{'headend'} } )
    {
        delete $headendURL{ $he[$a]->{'headend'} };
    }
    else
    {
        $headendURL{ $he[$a]->{'headend'} } = $he[$a]->{'url'};
    }
}

print "Creating .conf file.\n";
print "Do you want to save your password to the config file? (y/N): ";
chomp( $response = <STDIN> );
$response = uc($response);

open( $fh, ">", "tv_grab_na_sd.conf" );
print $fh "username:$username password:";
if ( $response eq "Y" )
{
    print $fh "$password";
}
print $fh " zipcode:$zipcode\n";
foreach ( sort keys %headendURL )
{
    print $fh "headend:$_ $headendURL{$_}\n";
}
close($fh);

print "Created .conf file. Re-run this script to download schedules.\n";

exit(0);

sub login_to_sd()
{
    my %req;

    $req{1}->{"action"}                = "get";
    $req{1}->{"object"}                = "randhash";
    $req{1}->{"request"}->{"username"} = $_[0];
    $req{1}->{"request"}->{"password"} = $_[1];
    $req{1}->{"api"}                   = $api;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );

    if ($debugenabled)
    {
        print "login_to_sd: created $json_text\n";
    }

    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server. Exiting.\n";
        exit;
    }

    return ( $response->{"randhash"} );
}

sub send_request()
{
    my $request = $_[0];

    if ($debugenabled)
    {

        print "send->request: request is\n$request\n";
    }

    $m->get("$baseurl/request.php");

    my $fields = { 'request' => $request };

    $m->submit_form( form_number => 1, fields => $fields, button => 'submit' );
    if ($debugenabled)
    {

        print "Response from server:\n" . $m->content();
    }

    return ( $m->content() );
}

sub download_schedules()
{

# Get the list of headends; open the files based on the hash
# pull in the files; parse each line, create a hash of station ID where value is URL
# Each stationid (key) can only be in the hash once, so we automatically de-dup.
# Loop through all hashes

    $randhash = $_[0];
    my $line;
    my %schedule_to_get;

    foreach $fn ( sort keys %headendURL )
    {
        open( $fh, "<", "$fn.txt" ) or die "Could not open $fn: $!\n";
        $line = <$fh>;
        chomp($line);
        close($fh);

        my $sched = JSON->new->utf8->decode($line);

        foreach my $e ( @{ $sched->{"StationID"} } )
        {
            $e->{url} =~ /p2=(\d{5})/;
            $schedule_to_get{$1} = $e->{url};
        }

        my $counter = 1;
        my $total   = keys(%schedule_to_get);

        print "$total to download.\n";

        foreach ( sort keys %schedule_to_get )
        {
            if ( $counter % 10 == 0 )
            {
                print "$counter of $total.\n";
            }

            $m->get( "$schedule_to_get{$_}&rand=" . $randhash );
            $m->save_content( $_ . "_sched.txt.gz" );
            $counter++;
        }
    }
}

sub print_status()
{
    $randhash = $_[0];
    print "Status messages from Schedules Direct:\n";

    my %req;

    $req{1}->{"action"}   = "get";
    $req{1}->{"object"}   = "status";
    $req{1}->{"randhash"} = $randhash;
    $req{1}->{"api"}      = $api;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugenabled)
    {

        print "print->status: json is $json_text\n";
    }
    my $status_message = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $status_message->{"response"} eq "ERROR" )
    {
        print "Received error from server. Exiting.\n";
        exit;
    }

    my $account_expiration = $status_message->{"Account"}->{"Expires"};
    print "Account expires on " . scalar localtime($account_expiration) . "\n";
    print "Maximum number of headends "
      . $status_message->{"Account"}->{"MaxHeadends"} . "\n";

    print "Last data update: ", $status_message->{"Last data update"}, "\n";

    foreach my $e ( @{ $status_message->{"Headend"} } )
    {
        print "Headend: ", $e->{ID}, " Modified: ",
          scalar localtime( $e->{Modified} ), "\n";
    }

    print "System notifications:\n";
    foreach my $f ( @{ $status_message->{Notifications} } )
    {
        print "\t$f\n" if $f ne "";
    }

    print "\n";
}

sub get_headends()
{
    $randhash = $_[0];
    my $to_get = "PC:" . $_[1];

    print "Retrieving headends.\n";

    my %req;

    $req{1}->{"action"}  = "get";
    $req{1}->{"object"}  = "headends";
    $req{1}->{"request"} = $to_get;
    $req{1}->{"api"}     = $api;

    if ( $randhash ne "none" )
    {
        $req{1}->{"randhash"} = $randhash;
    }

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugenabled)
    {

        print "get->headends: created $json_text\n";
    }
    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server. Exiting.\n";
        exit;
    }

    return ($response);

}

exit(0);
