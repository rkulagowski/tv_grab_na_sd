#!/usr/bin/perl -w
# Robert Kulagowski
# sudo apt-get install libwww-mechanize-perl

use strict;
use Getopt::Long;
use WWW::Mechanize;
use POSIX  qw(strftime);

my $version = "0.01";
my $date    = "2012-04-09";

my @lineupdata;
my $i              = 0;
my %headendURL;
my $username = "";
my $password = "";
my $help;
my $zipcode = "0";
my $randhash;
my $response;
my $debugenabled=0;
my $fn;
my $fh;
my $row = 0;
my @he;
my $m = WWW::Mechanize->new();

my $url="http://localhost/schedulesdirect/";
# my $url="http://rkulagow.schedulesdirect.org/";

GetOptions(
    'debug'       => \$debugenabled,
    'zipcode=s'   => \$zipcode,
    'username=s'  => \$username,
    'password=s'  => \$password,
    'help|?'      => \$help
);

if ($help) {
    print <<EOF;
tv_grab_na_sd.pl v$version $date
Usage: tv_grab_na_sd.pl [switches]

This script supports the following command line arguments.

--debug		Enable debug mode. Prints additional information
                to assist in troubleshooting any issues.

--username      Login credentials.
--password      Login credentials. NOTE: These will be visible in "ps".

--zipcode	When obtaining the channel list from Schedules Direct
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

if (-e "tv_grab_na_sd.conf")
{
  open ($fh, "<", "tv_grab_na_sd.conf");
  @lineupdata = <$fh>;
  chomp(@lineupdata);
  close ($fh);
  foreach (@lineupdata)
  {
    if ($_ =~ /^username:(\w+@[a-zA-Z_]+?\.[a-zA-Z]{2,6}) password:(.*) zipcode:(.{5,6})/)
    {
      $username = $1;
      $password = $2;
      $zipcode = $3;
    }
    if ($_ =~ /^headend:(\w+) (.+)/)
    {
      $headendURL{$1} = $2;
    }
  }

# Password is the only field to leave blank in the config file if you're
# paranoid about that sort of thing.
  if ($password eq "")
  {
    print "No password specified in .conf file.\nEnter password: ";
    chomp ($password = <STDIN>);
  }

  &login_to_sd($username, $password);

  print "Status messages from Schedules Direct:\n";
  $m->get("$url/process.php?command=get&p1=status&rand=$randhash");
  print $m->content();

  print "\nDownloading.\n";

  &get_headends();
  &download_schedules($randhash);

  print "Done.\n";
  exit(0);
}

# No configuration file, so we have to manually go through setup.
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

while (1)
{
    if ($zipcode =~ /^\d{5}$/ or $zipcode =~ /^[A-Z0-9]{6}$/)
    {
      last;
    }
    print "Please enter your zip code / postal code to download lineups.\n";
    print "5 digits for U.S., 6 characters for Canada: ";
    chomp ($zipcode = <STDIN>);
    $zipcode = uc($zipcode);
}

&login_to_sd($username, $password);

print "Status messages from Schedules Direct:\n";
$m->get("$url/process.php?command=get&p1=status&rand=$randhash");
print $m->content();

print "\n";

$m->get("$url/process.php?command=get&p1=headend&p2=$zipcode");
$m->save_content("available_headends.txt");

open( $fh, "<", "available_headends.txt" )
  or die "Fatal error: could not open available.txt: $!\n";
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

    while(1)
    {
    print "Queued\n";
    for my $j ( 0 .. $row ) 
    {
      if (defined $headendURL{$he[$j]->{'headend'}})
      {
        print "*";
      }
        print "\t$j. $he[$j]->{'name'}, $he[$j]->{'location'} ($he[$j]->{'headend'})\n";
    }
    print "\nEnter the number of the lineup you want to add / remove, 'D' for Done, 'Q' to exit: ";

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

    $a = $response*1;    # Numerify it.

    if ( $a < 0 or $a > $row ) 
    {
      print "Invalid choice.\n";
      next;
    }
    
    if (defined $headendURL{$he[$a]->{'headend'}})
    {
      delete $headendURL{$he[$a]->{'headend'}};
    }
    else
    {
      $headendURL{$he[$a]->{'headend'}} = $he[$a]->{'url'};
    }
    }

    print "Creating .conf file.\n";
    print "Do you want to save your password to the config file? (y/N): ";
    chomp( $response = <STDIN> );
    $response = uc($response);

open ($fh, ">", "tv_grab_na_sd.conf");
print $fh "username:$username password:";
if ($response eq "Y")
{
  print $fh "$password";
}
print $fh " zipcode:$zipcode\n";
foreach (sort keys %headendURL)
{
  print $fh "headend:$_ $headendURL{$_}\n";
}
close ($fh);

print "Created .conf file. Re-run this script to download schedules.\n";

exit(0);

sub login_to_sd()
{
  $m->get("$url/login.php");

  my $fields = { 'username' => $_[0], 'password' => $_[1] };

  $m->submit_form(form_number=>1, fields => $fields, button => 'submit');

  # Look for the randhash as a comment in the html page that we get back from
  # the server.
  $m->content() =~ /randhash: ([a-z0-9]+)/;
  $randhash = $1;

  if (not defined $randhash)
  {
    print "Incorrect username or password, or account not created at Schedules Direct. Exiting.\n";
    exit(1);
  }

}

sub get_headends()
{
  foreach $fn (sort keys %headendURL)
  {
    unless (-e "$fn.txt")
    {
      $m->get("$headendURL{$fn}");
      $m->save_content("$fn.txt.gz");
      system("gunzip --force $fn.txt.gz");
    }
  }
}

sub download_schedules()
{
  # Get the list of headends; open the files based on the hash
  # pull in the files; parse each line, create a hash of station ID where value is URL
  # loop through all hashes

  $randhash = $_[0];
  my %a;
  my $line;
  my $b;
  
  foreach $fn (sort keys %headendURL)
  {
    open ($fh, "<", "$fn.txt") or die "Could not open $fn: $!\n";
    while ($line = <$fh>)
    {
      if ($line =~ /^channel:(\d+) callsign:(\w+) stationid:(\d+) (.+)$/)
      {
        $a{$3} = $4;
      }
    }
    close ($fh);
  }

  foreach $i (sort keys %a)
  {
    $m->get($a{$i} . "&rand=" . $randhash);
    $m->save_content($i."_sched.txt.gz");
  }
  
}

exit(0);
