#!/usr/bin/perl -s

use strict;
use warnings;

use Fcntl qw(:flock);
use Cwd qw();
use XML::Simple qw(:strict);
# use Net::SMTP; # or
use Net::SMTP::SSL;

=begin COMMENT
PlCI is small and a simple continuous integration tool in Perl
http://en.wikipedia.org/wiki/Continuous_integration

For Now, this script is used to implement deployment / build / CI cycle for PHP projects only
Currently use PHPUnit and PHP Code Sniffer
New features coming soon: PHP Mess detector, PHP Copy Paste Detector and PHP Depend

For documentation, check the README.md file
=end COMMENT
=cut

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
#            GLOBAL CONFIGURATION            # 
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
use constant DEBUG => 0;
use constant LOGFILE => "/var/log/$0.log";
use constant CONFIG_PROJECT_NAME => "PROJECT TITLE";

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
#            EMAIL  CONFIGURATION            # 
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
# In the example below, we use the Gmail SMTP server for sending out email 
my %CONFIG_SMTP = (
    'from'    => 'mygmail.login@gmail.com',
    'ssl'     => 1,
    'smtp'    => 'smtp.gmail.com',
    'port'    => 465,
    'debug'   => 0,
    'timeout' => 30,
    # If the SMTP server requires authentication, complete the two lines below
    'auth_username' => 'mygmail.login@gmail.com',
    'auth_password' => 'thisIsMyPassword'
);
my @CONFIG_RECIPTIENTS = ('first.recpt@mail.org', 'second.recpt@mail.org'); # Accepte multiple recipients

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
#           REPOSITORY CONFIGURATION         #
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
use constant SERVER_TYPE => "svn";
# Complete path to the source to build
use constant SVN_SERV => "https://svn.sourceserver.beer/myproject/trunk";
use constant SVN_BIN => "/usr/bin/svn";
# You could set specifics parameters like the username and password. See below for an example:
# use constant SVN_BIN  => "/usr/bin/svn --username=SvnUserName --password=SvnPassword


# Local checkout path
# Can be (it's your choice) /current/tmp/... or /tmp/path_to/... 
use constant CI_PATH => Cwd::cwd() . "/tmp";
use constant CI_BUILD_PATH => CI_PATH . "/build";

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
#             PHPUNIT CONFIGURATION          #
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#

my $CONFIG_TESTCMD = "/usr/bin/php /usr/bin/phpunit --coverage-text=/tmp/coverage.log --log-tap=/tmp/result.log --bootstrap " . CI_BUILD_PATH . "/tests/bootstrap.php " . CI_BUILD_PATH . "/tests/";

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
#         CODE CHECKER CONFIGURATION         #
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#

my $CONFIG_CODECHECKCMD = "/usr/bin/php /usr/bin/phpcs --standard=PSR2 -n " . CI_BUILD_PATH;


# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
#             PREDEFINED VARIABLES           #
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#

my $ciFileName = $0;
# my $lockFile = '/path/to/the/revisionfile.pid';
my $lockFile = Cwd::cwd() . '/' . $ciFileName . '.pid';

my $revision = 0;
my @ciResults = ();
my $globalResultStatus = "OK"; # Could be "OK", "WARNING", "FAILURE"

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
#             CHECKOUT & BUILD               #
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
# Open log file
my $FH_LOG;
if (DEBUG == 1) {
    open($FH_LOG, ">>", LOGFILE) or die "error: trying to open the file '" . LOGFILE . ": $!";
}

# Get the last stored revision
# Open the revision file or create it if it doesn't exist
open(my $REVISIONFILE, ">>$lockFile") or die "error: trying to open the file '$lockFile': $!"; # create if not there
open($REVISIONFILE, "<", $lockFile)  or die "error: trying to open the file '$lockFile': $!";  # and open it for reading

# Check if this script is already launched
unless (flock($REVISIONFILE, LOCK_EX|LOCK_NB)) {
    die "error: $ciFileName is already running. Exiting.";
}

if (read($REVISIONFILE, my $readLine, 100)) {
    $revision = int $readLine;
} else {
    $revision = 0;
}

unless(-e CI_PATH or mkdir CI_PATH) {
    die "Unable to create " . CI_PATH;
}

# Check for the last HEAD commit
my $command = SVN_BIN . " info --xml " . SVN_SERV;
my $infos = `$command`;

my $newRevision = 0;

if ($infos =~ /revision="(\d+)"/) {
    $newRevision = int $1;
} else {
    die "error: trying to get the last revision with the command '$command'";
}

if ($newRevision == $revision) {
    print "There are no change since the last build. Exiting\n";
    exit 0;
}

# Checkout the last revision
my $revPath = CI_PATH . "/" . $newRevision;
$command = SVN_BIN . " export " . SVN_SERV . " " . CI_BUILD_PATH;
$infos = `$command`;

my $message = "";

# execute tests
$message = $message . runUITest();

# execute code checker
$message = $message . runCodeChecker(); 

# sending result by mail
sendEmail($message);

# Close the lock file
close($REVISIONFILE);

# Saving the revision of the last builded source
open($REVISIONFILE, '>', $lockFile) or die "error: trying to open the file '$lockFile': $!";
seek ($REVISIONFILE, 0, 1);
print $REVISIONFILE "$newRevision";

# Close the lock file
close($REVISIONFILE);

# @Todo: archive release if $globalResultStatus = 'OK'

# Clean Build Folder
executeCommand("/bin/rm -Rf " . CI_BUILD_PATH);

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
# F()       SENDING E-MAIL REPORT            #
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
sub sendEmail {
    my $n = scalar(@_);
    if ($n != 1) {
        die('error: the message could not be sent because there are no message to send.');
    }
    my ($message) = @_;
    my $smtp;
    if ($CONFIG_SMTP{'ssl'} == 1) {
        $smtp = Net::SMTP::SSL->new($CONFIG_SMTP{'smtp'}, Port => $CONFIG_SMTP{'port'}, Debug => $CONFIG_SMTP{'debug'}, Timeout => $CONFIG_SMTP{'timeout'}) or die "Could not connect to the SMTP server\n";
    } else {
        $smtp = Net::SMTP->new($CONFIG_SMTP{'smtp'}, Port => $CONFIG_SMTP{'port'}, Debug => $CONFIG_SMTP{'debug'}, Timeout => $CONFIG_SMTP{'timeout'}) or die "Could not connect to the SMTP server\n";
    }

    # If the SMTP server requires an authentication
    if (defined $CONFIG_SMTP{'auth_username'}) {
        $smtp->auth($CONFIG_SMTP{'auth_username'}, $CONFIG_SMTP{'auth_password'}) or die "Authentication failed!\n";
    }

    $smtp->mail($CONFIG_SMTP{'from'} . "\n");
    foreach my $recp (@CONFIG_RECIPTIENTS) {
        $smtp->to($recp . "\n");
    }
    $smtp->data();
    $smtp->datasend("From: " . $CONFIG_SMTP{'from'} . "\n");
    foreach my $recp (@CONFIG_RECIPTIENTS) {
        $smtp->datasend("To: " . $recp . "\n");
    }
    $smtp->datasend("Subject: [PlCI] " . CONFIG_PROJECT_NAME . " rev " . $newRevision . ": " . $globalResultStatus . "\n");
    $smtp->datasend("\n");
    $smtp->datasend($message . "\n");
    $smtp->dataend();
    $smtp->quit;
}

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
#  F()        RUNNING UNIT TESTS             #
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
sub runUITest {

    $infos = `$CONFIG_TESTCMD`;

    # Check results
    my $message =         "*************\n";
    $message = $message . "PHPUNIT TESTS\n";
    $message = $message . "*************\n";

    my $logfile;

    open $logfile, '<', "/tmp/coverage.log" or die "error opening '/tmp/coverage.log': $!";
    my $coverage = do { local $/; <$logfile> };
    close $logfile;

    open $logfile, '<', "/tmp/result.log" or die "error opening '/tmp/result.log': $!";
    my $phpunitlog = do { local $/; <$logfile> };
    close $logfile;

    # Check result
    if ($infos =~ /OK \(/) {
        $message = $message . "RESULT: Build $newRevision have successfully passed all test processes.\n\n";
    } else {
        $globalResultStatus = "FAILURE";
        $message = $message . "RESULT: Build $newRevision has failed to pass the test processes.\n\n"; 
        $message = $message . "RESULT:\n" . $infos . "\n\n";
    }
    $message = $message . $phpunitlog . "\n\n";
    $message = $message . "*************\n";
    $message = $message . "CODE COVERAGE\n";
    $message = $message . "*************\n";
    $message = $message . $coverage;
    
    return $message;
}

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
#  F()      RUNNING CODE CHECKER             #
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
sub runCodeChecker {
    my $message = "";
    
    $infos = `$CONFIG_CODECHECKCMD`;

    # Check result
    if ($infos =~ /FOUND \d+ ERROR/) {
        if ($globalResultStatus ne '') {
            $globalResultStatus = "WARNING"; # or "FAILURE;
        }
        $message = $message . "*************\n";
        $message = $message . "CODE CHECKER \n";
        $message = $message . "*************\n";
        $message = $message . "RESULT: Build $newRevision has failed to pass the code checker.\n\n"; 
        $message = $message . "RESULT:\n" . $infos . "\n\n";
    }
    return $message;
}

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
#  F()        EXECUTE SYSTEM CMD             #
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
sub executeCommand
{
    my $execCmd = $_[0];

    info ("executing [$execCmd]", "LOG");
    my $returnCode = system( $execCmd );

    if ( $returnCode != 0 ) 
    { 
        info ("Failed executing [$execCmd]", "ERR");
        die "Failed executing [$execCmd]\n"; 
    }
}

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
#  F()                  LOG                  #
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;#
sub info
{
    my ($msg, $type) = @_;
    return if (DEBUG == 0);

    print $FH_LOG "$type: $msg \n";

} 