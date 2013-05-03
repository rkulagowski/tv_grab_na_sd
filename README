Robert Kulagowski
grabber@schedulesdirect.org

v0.21 2013-05-02

Please see the Wiki at https://github.com/rkulagowski/tv_grab_na_sd/wiki for
information regarding the format and the field descriptions.

This grabber uses the new Schedules Direct API for downloading schedule
information directly from Schedules Direct.

You must have the following perl modules installed for this script to
function correctly:

$ sudo apt-get install libwww-mechanize-perl libjson-perl libjson-xs-perl
$ sudo apt-get install libdigest-sha-perl

if you're on Ubuntu.

When run with --help, the script will print:

=================================================
tv_grab_sd.pl v0.21 2013-05-02
Usage: tv_grab_sd.pl [switches]

This script supports the following command line arguments.

--beta                  Use the beta server to test new features. If not
                        specified, default to production server.

--configure             Re-runs the configure sequence and ignores any
                        existing tv_grab_sd.conf file.  You may still pass
                        login credentials and zipcode if you want to bypass
                        interactive configuration.

--debug                 Enable debug mode. Prints additional information to
                        assist in troubleshooting any issues.

--username              Login credentials.
--password              Login credentials. NOTE: These will be visible in "ps".

--zipcode               When obtaining the channel list from Schedules
                        Direct you can supply your 5-digit zip code or
                        6-character postal code to get a list of cable TV
                        providers in your area, otherwise you'll be
                        prompted.  If you're specifying a Canadian postal
                        code, then use six consecutive characters, no
                        embedded spaces.

--changepassword        Enters the password change dialog on the client.

--metadataupdate        Updates incorrect metdata.

--metadata              Retrieve all metadata.

--add                   Add a headend.

--delete                Delete a headend.

--ack                   Acknowlege a message, so that it doesn't appear
                        in the status object.

--help                  This screen.

Bug reports to grabber@schedulesdirect.org  Include the .conf file and the
complete output when the script is run with --debug

NOTE: This grabber is intended for developers who wish to have a starting
point for their own efforts.  There is very little bug checking and it is
not optimized in any way.

=================================================

When the script is run for the first time, if you don't pass --username
--password and --zipcode as command-line parameters, you'll be prompted for
your Schedules Direct account information.

Once your account has been validated, the script will download the list of
headends in your zip code / postal code. Type the number of the headend you
will be using. If you change your mind, type the same number to remove the
headend from the queue. You may select multiple headends.

When the headend selection phase is complete, the script will exit, and will
inform you to re-run the script to begin the download process.

When the script is run with a valid tv_grab_na_sd.conf file, it will
download to the current directory.

NOTE: As of 2013-01-17, the grabber is only a "shell"; it is primarily
intended for developers to use as a reference for their own development.

The included tv_grab_sd.conf file contains some examples of how to retrieve
various JSON objects from the server and one possible way that they could be
parsed in perl. This program is not intended to be a full-featured grabber
for users without extensive modification.

The beta service is open to all Schedules Direct users. Developers should
use the "Developers Corner" forum at

http://http://forums.schedulesdirect.org/viewforum.php?f=8

for assistance.
