# PlCI

## INTRODUCTION

PlCI is small and a simple continuous integration Perl tool
(http://en.wikipedia.org/wiki/Continuous_integration)

For Now, this script is used to implement deployment / build / CI cycle for PHP projects only
Currently use PHPUnit and PHP Code Sniffer
New features coming soon: PHP Mess detector, PHP Copy Paste Detector and PHP Depend

This script do:
- The script check if there are changes since the last run
- It runs a svn update on a source folder (@TODO use git or mercurial too)
- If true, it run tests and defined controls
- Email, report and store the status of this test (success or failure) and the complete output


TODO and not yet implemented:
- Archive the builded release (can be flagged as a future release)
- Using git/Mercurial as a version-control system
- Create an HTML report (full path will be configured, can be browsed)
- Possibility to use an external configuration file to extend/replace PlCI configuration
- Launching some externals and specific scripts
- More Log informations

## Documentation

Use a cron (like crontab) to periodically run this script on a server
30 2 * * * /usr/bin/perl /home/user/path/to/ci.pl

To finish configuring your PlCI installation, please complete these informations

CONFIG_PROJECT_NAME: The project name / title

%CONFIG_SMTP: Configure this with your SMTP relay
note: you will be allowed to use sendmail in the future

@CONFIG_RECIPTIENTS: To send the report to a list of recipients, please complete this array. It define the list of recipients that you want to include in the mailing

SVN_SERV: Complete path to the source to build
SVN_BIN: The svn binary executable, normally installed in /usr/bin or /usr/local/bin on your machine/server

You could modify the CI_PATH and CI_BUILD_PATH
It's used to specify where the project will be built and tested

$CONFIG_TESTCMD: the command line used to run PHPUnit for this project

$CONFIG_CODECHECKCMD: the command line used to execute PHP Code Sniffer