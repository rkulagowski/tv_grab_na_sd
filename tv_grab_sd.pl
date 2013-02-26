#!/usr/bin/perl -w
# Robert Kulagowski
# sudo apt-get install libwww-mechanize-perl libjson-perl libjson-xs-perl libdigest-sha-perl

use strict;
use Getopt::Long;
use WWW::Mechanize;
use POSIX qw(strftime);
use JSON;
use Data::Dumper;
use Digest::SHA qw(sha1_hex);

# If you're not insane like Ubuntu (https://bugs.launchpad.net/ubuntu/+source/libdigest-sha1-perl/+bug/993648)
# you probably want
# use Digest::SHA1 qw(sha1_hex);

my $version = "0.20";
my $date    = "2013-02-26";

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
my $debugenabled   = 0;
my $configure      = 0;
my $changepassword = 0;
my $metadata       = 0;
my $metadataupdate = 0;
my $addHeadend     = "";
my $deleteHeadend  = "";
my $useBetaServer  = 0;
my $ackMessage     = 0;
my $fh;
my $row = 0;
my @he;
my $m = WWW::Mechanize->new(
    agent   => "tv_grab_na.pl developer grabber v$version/$date",
    timeout => 60 * 10
);
my $getOnlyMySubscribedLineups = 0;
my %req;
my %scheduleToGet;
my %programToGet;
my $baseurl;

# API must match server version.
my $api = 20130224;

GetOptions(
    'debug'          => \$debugenabled,
    'configure'      => \$configure,
    'zipcode=s'      => \$zipcode,
    'username=s'     => \$username,
    'password=s'     => \$password,
    'changepassword' => \$changepassword,
    'metadataupdate' => \$metadataupdate,
    'metadata'       => \$metadata,
    'beta'           => \$useBetaServer,
    'add=s'          => \$addHeadend,
    'delete=s'       => \$deleteHeadend,
    'ack=s'          => \$ackMessage,
    'help|?'         => \$help
);

if ($useBetaServer)
{
    # Test server. Things may be broken there.
    $baseurl = "http://23.21.174.111";
    print "Using beta server.\n";
}
else
{
    $baseurl = "https://data2.schedulesdirect.org";
    print "Using production server.\n";
}

if ($help)
{
    print <<EOF;
tv_grab_sd.pl v$version $date
Usage: tv_grab_sd.pl [switches]

This script supports the following command line arguments.

--beta			Use the beta server to test new features. If not
                        specified, default to production server.

--configure		Re-runs the configure sequence and ignores any
                        existing tv_grab_sd.conf file.  You may still pass
                        login credentials and zipcode if you want to bypass
                        interactive configuration.

--debug			Enable debug mode. Prints additional information to
                        assist in troubleshooting any issues.

--username      	Login credentials.
--password      	Login credentials. NOTE: These will be visible in "ps".

--zipcode       	When obtaining the channel list from Schedules
                        Direct you can supply your 5-digit zip code or
                        6-character postal code to get a list of cable TV
                        providers in your area, otherwise you'll be
                        prompted.  If you're specifying a Canadian postal
                        code, then use six consecutive characters, no
                        embedded spaces.

--changepassword	Enters the password change dialog on the client.

--metadataupdate	Updates incorrect metdata.

--metadata	        Retrieve all metadata.

--add			Add a headend.

--delete		Delete a headend.

--ack			Acknowlege a message, so that it doesn't appear
                        in the status object.

--help          	This screen.

Bug reports to grabber\@schedulesdirect.org  Include the .conf file and the
complete output when the script is run with --debug

NOTE: This grabber is intended for developers who wish to have a starting
point for their own efforts.  There is very little bug checking and it is
not optimized in any way.

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
        if ( $_ =~ /^headend:(\S+) (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)/ )
        {
            $headendModifiedDate_local{$1} = $2;
        }
        if ( $_ =~ /^station:(\d+)/ )
        {
            $scheduleToGet{$1} =
              1;    # Set it to a dummy value just to populate the hash.
        }
        if ( $_ =~ /^program:([[:alnum:]]{14})/ )
        {
            $programToGet{$1} =
              1;    # Set it to a dummy value just to populate the hash.
        }

# The following is dead code for now; when we request metadata from the server it's going to
# send everything.
#        if ( $_ =~ /^metadata:([[:alnum:]]{14})/ )
#        {
#            $metadataToGet{$1} =
#              1;    # Set it to a dummy value just to populate the hash.
#        }
    }

    # Password is the only field to leave blank in the config file if you're
    # paranoid about that sort of thing.
    if ( $password eq "" )
    {
        print "No password specified in .conf file.\nEnter password: ";
        chomp( $password = <STDIN> );
    }

    $randhash = &login_to_sd( $username, $password );

    if ($changepassword)
    {

        print "New password: ";
        my $pass1 = <STDIN>;
        print "Confirm new password: ";
        my $pass2 = <STDIN>;

        if ( $pass1 ne $pass2 )
        {
            print "\nPasswords did not match. Exiting.\n";
            exit;
        }

        chomp($pass2);

        &change_password($pass2);

        exit;

    }

    if ($metadataupdate)
    {
        &metadata_update( $randhash, "EP002930532006", "0", "71256", "thetvdb",
            "seriesid", "Please update as soon as possible." );
        exit;
    }

    &print_status($randhash);

    if ( $addHeadend ne "" || $deleteHeadend ne "" )
    {

        my ( $headend, $action );
        if ( $addHeadend ne "" )
        {
            $headend = $addHeadend;
            $action  = "add";
            print "Adding headend: $headend\n";

        }
        else
        {
            $headend = $deleteHeadend;
            $action  = "delete";
            print "Deleteing headend: $headend\n";
        }

        &add_or_delete_headend( $randhash, $headend, $action );
        exit;

    }

    print "\nDownloading.\n";

    foreach my $e ( keys %headendModifiedDate_local )
    {
        if ( $headendModifiedDate_local{$e} ne $headendModifiedDate_Server{$e} )
        {
            print "Updated lineup $e: local version $headendModifiedDate_local{$e}, ";
            print "server version $headendModifiedDate_Server{$e}\n";
            &download_lineup( $randhash, $e );
        }
    }

    #    &get_headends();
    if ( keys %scheduleToGet > 0 )
    {
        &download_schedules($randhash);
    }
    if ( keys %programToGet > 0 )
    {
        &download_programs($randhash);
    }

    if ($metadata)
    {
        &downloadMetadata($randhash);
    }

    if ($ackMessage)
    {
        &ackMessage( $randhash, $ackMessage );
    }

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
    print "Please enter your zip code / postal code to ";
    print "download headends for your area.\n";
    print "5 digits for U.S., 6 characters for Canada: ";
    chomp( $zipcode = <STDIN> );
    $zipcode = uc($zipcode);
}

$randhash = &login_to_sd( $username, $password );
&print_status($randhash);

# If the randhash is sent, then we're going to get only the headends that the
# user has already configured.  No randhash means all possible headends in
# this zip / postal code.

if ($getOnlyMySubscribedLineups)
{
    $response = &get_headends( $randhash, "" );
}
else
{
    $response = &get_headends( $randhash, $zipcode );

}

foreach my $e ( @{ $response->{"data"} } )
{
    $he[$row]->{'headend'}  = $e->{headend};
    $he[$row]->{'name'}     = $e->{name};
    $he[$row]->{'location'} = $e->{location};
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
    print "\nEnter the number of the lineup you want to add / remove,";
    print " 'D' for Done, 'Q' to exit: ";

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
chomp( my $savePassword = <STDIN> );
$savePassword = uc($savePassword);

print "Send \"add headend\" command to server? (y/N): ";
chomp( my $sendAddHeadendCommandToServer = <STDIN> );
$sendAddHeadendCommandToServer = uc($sendAddHeadendCommandToServer);
if ( $sendAddHeadendCommandToServer eq "Y" )
{
    print "Getting credentials.\n";
    $randhash = &login_to_sd( $username, $password );
}

open( $fh, ">", "tv_grab_sd.conf" );
print $fh "username:$username password:";
if ( $savePassword eq "Y" )
{
    print $fh "$password";
}
print $fh " zipcode:$zipcode\n";
foreach ( sort keys %headend_queued )
{
    print $fh "headend:$_ 1970-01-01T00:00:00Z\n";
    if ( $sendAddHeadendCommandToServer eq "Y" )
    {
        &add_or_delete_headend( $randhash, $_, "add" );
    }
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

# If there's a file name, then the response is going to be a .zip file, and
# we don't want to try to print a zip.
# NOTE: as of 20130224 the API no longer directly sends .zip files; it will include
# a link to the file to download.

    {
        print "Response from server:\n" . $m->content();
    }

    if ( $fname eq "" )
    {
        return ( $m->content() ); # Just return whatever we got from the server.
    }

    $fname =~ s/PC:/PC_/;

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
    $req{1}->{"request"}->{"password"} = sha1_hex( $_[1] );
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

    my $account_expiration = $response->{"account"}->{"expires"};
    print "Account expires on $account_expiration\n";
    print "Maximum number of headends "
      . $response->{"account"}->{"maxHeadends"} . "\n";

    print "Last data update: ", $response->{"lastDataUpdate"}, "\n";

    foreach my $e ( @{ $response->{"headend"} } )
    {
        print "Headend: ", $e->{ID}, " Modified: ", $e->{modified}, "\n";
        $headendModifiedDate_Server{ $e->{ID} } = $e->{modified};
    }

    print "System notifications:\n";
    foreach my $f ( @{ $response->{notifications} } )
    {
        print "msgID:$f->{msgID} date:$f->{date} Message:$f->{message}\n";
    }

    #    foreach my $f ( @{ $response->{notifications} } )
    #    {
    #        print "\t$f\n" if $f ne "";
    #    }

    print "Messages for you:\n";

    foreach my $g ( @{ $response->{account}->{messages} } )
    {
        print "msgID:$g->{msgID} date:$g->{date} Message:$g->{message}\n";
    }

    print "Next suggested connect time: "
      . $response->{"account"}->{"nextSuggestedConnectTime"} . "\n";

    print "\n";
}

sub download_schedules()
{
    # Receives a .zip file from the server.
    $randhash = $_[0];

    my $total = keys(%scheduleToGet);

    print "$total station schedules to download.\n";

    my %req;

    $req{1}->{"action"}   = "get";
    $req{1}->{"randhash"} = $randhash;
    $req{1}->{"object"}   = "schedules";
    $req{1}->{"api"}      = $api;

    my @tempArray;

    foreach ( keys %scheduleToGet )
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
    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    my $url      = $response->{"URL"};
    my $fileName = $response->{"filename"};

    print "url is: $url\n";
    $m->get( $url, ':content_file' => $fileName );

}

sub download_programs()
{
    # Receives a .zip file from the server.
    
    $randhash = $_[0];

    my $total = keys(%programToGet);

    print "$total programs to download.\n";

    my %req;

    $req{1}->{"action"}   = "get";
    $req{1}->{"randhash"} = $randhash;
    $req{1}->{"object"}   = "programs";
    $req{1}->{"api"}      = $api;

    my @tempArray;

    foreach ( keys %programToGet )
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
    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    my $url      = $response->{"URL"};
    my $fileName = $response->{"filename"};

    print "url is: $url\n";
    $m->get( $url, ':content_file' => $fileName );

}

sub get_headends()
{

    # This function returns the headends which are available in a particular
    # geographic location.

    $randhash = $_[0];
    my $to_get;

    if ( $_[1] ne "" )
    {
        $to_get = "PC:" . $_[1];
    }
    else
    {
        $to_get = "";
    }

    print "Retrieving headends.\n";

    my %req;

    $req{1}->{"action"}   = "get";
    $req{1}->{"object"}   = "headends";
    $req{1}->{"request"}  = $to_get;
    $req{1}->{"api"}      = $api;
    $req{1}->{"randhash"} = $randhash;

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
    # Receives a .zip file from the server.

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
    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    my $url      = $response->{"URL"};
    my $fileName = $response->{"filename"};

    print "url is: $url\n";
    $m->get( $url, ':content_file' => $fileName );

}

sub change_password()
{
    my $newpassword = $_[0];
    print "Sending new password ($newpassword) change request to server.\n";
    my %req;

    $req{1}->{"action"}                   = "update";
    $req{1}->{"object"}                   = "password";
    $req{1}->{"randhash"}                 = $randhash;
    $req{1}->{"request"}->{"newPassword"} = sha1_hex($newpassword);
    $req{1}->{"api"}                      = $api;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugenabled)
    {
        print "update->password: created $json_text\n";
    }
    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    print "Successfully updated password.\n";

}

sub metadata_update()
{
    my $randhash        = $_[0];
    my $prog_id         = $_[1];
    my $current_value   = $_[2];
    my $suggested_value = $_[3];
    my $source          = $_[4];
    my $whattoupdate    = $_[5];
    my $comment         = $_[6];

    print "Sending metadata update change request to server.\n";
    my %req;

    $req{1}->{"action"}                 = "update";
    $req{1}->{"object"}                 = "metadata";
    $req{1}->{"randhash"}               = $randhash;
    $req{1}->{"request"}->{"prog_id"}   = $prog_id;
    $req{1}->{"request"}->{"current"}   = $current_value;
    $req{1}->{"request"}->{"suggested"} = $suggested_value;
    $req{1}->{"request"}->{"source"}    = $source;
    $req{1}->{"request"}->{"field"}     = $whattoupdate;
    $req{1}->{"request"}->{"comment"}   = $comment;

    $req{1}->{"api"} = $api;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugenabled)
    {
        print "update->metadata: created $json_text\n";
    }
    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    print "Successfully sent metadata update request.\n";

}

sub add_or_delete_headend()
{

    # Order of parameters:randhash,headend,action

    my %req;

    if ( $_[2] eq "add" )
    {
        print "Sending addHeadend request to server.\n";
        $req{1}->{"action"} = "add";
    }

    if ( $_[2] eq "delete" )
    {
        print "Sending deleteHeadend request to server.\n";
        $req{1}->{"action"} = "delete";
    }

    $req{1}->{"object"}   = "headends";
    $req{1}->{"randhash"} = $_[0];
    $req{1}->{"request"}  = $_[1];

    $req{1}->{"api"} = $api;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugenabled)
    {
        print "add/delete->headend: created $json_text\n";
    }
    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    print "Successfully sent Headend request.\n";

    if ($debugenabled)
    {
        print Dumper($response);
    }

    return;

}

sub ackMessage()
{
    my %req;
    $randhash = $_[0];
    my $to_del = $_[1];

    # Note: you can also ACK multiple messages by passing an array of msgIDs in
    # the request to the server.

    $req{1}->{"action"}   = "delete";
    $req{1}->{"randhash"} = $randhash;
    $req{1}->{"object"}   = "message";
    $req{1}->{"request"}  = [$to_del];
    $req{1}->{"api"}      = $api;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugenabled)
    {
        print "ackMessage: created $json_text\n";
    }
    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }
    print "Successfully sent delete message request.\n";
    if ($debugenabled)
    {
        print Dumper($response);
    }

    return;

}

sub downloadMetadata()
{

    # Gets a .zip file from the server.
    
    my %req;
    my @tempArray;
    my $modified;

    $randhash = $_[0];

    # At some point we may dynamically generate metadata on the server, but as
    # of 2013-02-21 it's a static file, so we don't need to generate a "fancy"
    # request.



    #    foreach ( keys %metadataToGet )
    #    {
    #        if ($debugenabled) { print "to get: $_\n"; }
    #        push( @tempArray, $_ );
    #    }

    $req{1}->{"action"}   = "get";
    $req{1}->{"randhash"} = $randhash;
    $req{1}->{"object"}   = "metadata";

    #    $req{1}->{"modified"} = $metadata + 0;
    #    $req{1}->{"request"}  = \@tempArray;
    $req{1}->{"api"} = $api;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugenabled)
    {
        print "download->metadata: created $json_text\n";
    }

    #    my $response = JSON->new->utf8->decode(
    #        &send_request( $json_text, "metadata.json.zip" ) );

    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    my $url      = $response->{"URL"};
    my $fileName = $response->{"filename"};

    print "url is: $url\n";
    $m->get( $url, ':content_file' => $fileName );

}

exit(0);
