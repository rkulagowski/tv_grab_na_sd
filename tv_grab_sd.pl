#!/usr/bin/perl -w
# Robert Kulagowski
# sudo apt-get install libwww-mechanize-perl libjson-perl libjson-xs-perl

use strict;
use Getopt::Long;
use WWW::Mechanize;
use POSIX qw(strftime);
use JSON;
use Data::Dumper;

my $version = "0.12";
my $date    = "2012-12-20";

my @lineupdata;
my $i = 0;
my %headendModifiedDate_local;
my %headendModifiedDate_Server;
my %headend_queued;
my $username = "";
my $password = "";
my $help;
my $zipcode = "0";
my $randhash;
my $response;
my $debugenabled = 0;
my $configure    = 0;
my $fh;
my $row = 0;
my @he;
my $m                      = WWW::Mechanize->new();
my $get_all_lineups_in_zip = 0;
my %req;
my %schedule_to_get;
my %program_to_get;

# API must match server version.
my $api = 20121217;

# If we specify a randhash, we only get back the configured lineups in our
# account, otherwise you get everything in your postal code.

# The root of the download location for testing purposes.

#my $baseurl = "http://ec2-23-21-174-111.compute-1.amazonaws.com";
my $baseurl = "http://SD-lb-1362972613.us-east-1.elb.amazonaws.com";

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
tv_grab_sd.pl v$version $date
Usage: tv_grab_sd.pl [switches]

This script supports the following command line arguments.

--configure     Re-runs the configure sequence and ignores any existing
                tv_grab_sd.conf file. You may still pass login
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

if ( -e "tv_grab_sd.conf" && $configure == 0 )
{
    open( $fh, "<", "tv_grab_sd.conf" );
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
        if ( $_ =~ /^headend:(\S+) (\d+)/ )
        {
            $headendModifiedDate_local{$1} = $2;
        }
        if ( $_ =~ /^station:(\d+)/ )
        {
            $schedule_to_get{$1} =
              1;    # Set it to a dummy value just to populate the hash.
        }
        if ( $_ =~ /^program:([[:alnum:]]{14})/ )
        {
            $program_to_get{$1} =
              1;    # Set it to a dummy value just to populate the hash.
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

    foreach my $e ( keys %headendModifiedDate_local )
    {
        if ( $headendModifiedDate_local{$e} != $headendModifiedDate_Server{$e} )
        {
            print
"Updated lineup $e: local version $headendModifiedDate_local{$e}, server version $headendModifiedDate_Server{$e}\n";
            &download_lineup( $randhash, $e );
        }
    }

    #    &get_headends();
    &download_schedules($randhash);
    &download_programs($randhash);

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

if ( $get_all_lineups_in_zip == 1 )
{
    $response = &get_headends( "none", $zipcode );
}
else
{
    $response = &get_headends( $randhash, $zipcode );
}

foreach my $e ( @{ $response->{"data"} } )
{
    $he[$row]->{'headend'}  = $e->{headend};
    $he[$row]->{'name'}     = $e->{Name};
    $he[$row]->{'location'} = $e->{Location};
    $row++;
}

$row--;

while (1)
{
    print "Queued\n";
    for my $j ( 0 .. $row )
    {
        if ( defined $headend_queued{ $he[$j]->{'headend'} } )
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

    if ( defined $headend_queued{ $he[$a]->{'headend'} } )
    {
        delete $headend_queued{ $he[$a]->{'headend'} };
    }
    else
    {
        $headend_queued{ $he[$a]->{'headend'} } = $he[$a]->{'headend'};
    }
}

print "Creating .conf file.\n";
print "Do you want to save your password to the config file? (y/N): ";
chomp( $response = <STDIN> );
$response = uc($response);

open( $fh, ">", "tv_grab_sd.conf" );
print $fh "username:$username password:";
if ( $response eq "Y" )
{
    print $fh "$password";
}
print $fh " zipcode:$zipcode\n";
foreach ( sort keys %headend_queued )
{
    print $fh "headend:$_ 0\n";
}
close($fh);

print "Created .conf file. Re-run this script to download schedules.\n";

exit(0);

sub send_request()
{

    # The workhorse routine. Creates a JSON object and sends it to the server.

    my $request = $_[0];
    my $fname   = "";

    if ( defined $_[1] )
    {
        $fname = $_[1];
    }

    if ($debugenabled)
    {
        print "send->request: request is\n$request\n";
    }

    $m->get("$baseurl/request.php");

    my $fields = { 'request' => $request };

    $m->submit_form( form_number => 1, fields => $fields, button => 'submit' );
    if ( $debugenabled && $fname eq "" )

# If there's a file name, then the response is going to be a .zip file, and we don't want to try to print a zip.
    {
        print "Response from server:\n" . $m->content();
    }

    if ( $fname eq "" )
    {
        return ( $m->content() ); # Just return whatever we got from the server.
    }

    $m->save_content($fname);

    # Make a json response so that other functions don't need to get re-written
    my %response;
    $response{1}->{code}     = 200;
    $response{1}->{response} = "OK";
    my $json1 = new JSON::XS;
    return ( $json1->utf8(1)->encode( $response{1} ) );
}

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
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    return ( $response->{"randhash"} );
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
    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    my $account_expiration = $response->{"Account"}->{"Expires"};
    print "Account expires on " . scalar localtime($account_expiration) . "\n";
    print "Maximum number of headends "
      . $response->{"Account"}->{"MaxHeadends"} . "\n";

    print "Last data update: ", $response->{"Last data update"}, "\n";

    foreach my $e ( @{ $response->{"Headend"} } )
    {
        print "Headend: ", $e->{ID}, " Modified: ",
          scalar localtime( $e->{Modified} ), "\n";
        $headendModifiedDate_Server{ $e->{ID} } = $e->{Modified};
    }

    print "System notifications:\n";
    foreach my $f ( @{ $response->{Notifications} } )
    {
        print "\t$f\n" if $f ne "";
    }

    print "\n";
}

sub download_schedules()
{
    $randhash = $_[0];

    my $total = keys(%schedule_to_get);

    print "$total station schedules to download.\n";

    my %req;

    $req{1}->{"action"}   = "get";
    $req{1}->{"randhash"} = $randhash;
    $req{1}->{"object"}   = "schedules";
    $req{1}->{"api"}      = $api;

    my @tempArray;

    foreach ( keys %schedule_to_get )
    {
        if ($debugenabled) { print "to get: $_\n"; }
        push( @tempArray, $_ );
    }

    $req{1}->{"request"} = \@tempArray;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugenabled)
    {
        print "download->schedules: created $json_text\n";
    }
    my $response = JSON->new->utf8->decode(
        &send_request( $json_text, "schedules.json.zip" ) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }
}

sub download_programs()
{
    $randhash = $_[0];

    my $total = keys(%program_to_get);

    print "$total programs to download.\n";

    my %req;

    $req{1}->{"action"}   = "get";
    $req{1}->{"randhash"} = $randhash;
    $req{1}->{"object"}   = "programs";
    $req{1}->{"api"}      = $api;

    my @tempArray;

    foreach ( keys %program_to_get )
    {
        if ($debugenabled) { print "to get: $_\n"; }
        push( @tempArray, $_ );
    }

    $req{1}->{"request"} = \@tempArray;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugenabled)
    {
        print "download->programs: created $json_text\n";
    }
    my $response = JSON->new->utf8->decode(
        &send_request( $json_text, "programs.json.zip" ) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }
}

sub get_headends()
{

    # This function returns the headends which are available in a particular
    # geographic location.

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
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    return ($response);

}

sub download_lineup()
{

    # A lineup is a specific mapping of channels for a provider.

    $randhash = $_[0];
    my $to_get = $_[1];
    print "Retrieving lineup $to_get.\n";

    my %req;

    $req{1}->{"action"}   = "get";
    $req{1}->{"randhash"} = $randhash;
    $req{1}->{"object"}   = "lineups";
    $req{1}->{"request"}  = [$to_get];
    $req{1}->{"api"}      = $api;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugenabled)
    {
        print "download->lineup: created $json_text\n";
    }
    my $response = JSON->new->utf8->decode(
        &send_request( $json_text, "$to_get.json.zip" ) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

}

exit(0);