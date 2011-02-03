#!/usr/bin/perl

use DBI;

my $dbh, $mf, @qresult, $checkmfexistsquery, $insertquery;
$dbh = DBI->connect("dbi:SQLite:dbname=/home/anup/.mftracker/mftracker.db", "", "");

if ($#ARGV == 3) {
	my ($mfid, $sipamount, $sipdate, $installments) = @ARGV;
	print "Adding sip for $mfid...\n";
	$insertquery = "INSERT INTO sips VALUES(NULL, '$mfid', $sipamount, $sipdate, $installments)";
	$dbh->do($insertquery);
}
else {
	print "Usage: addsip.pl <MFId> <SIP Amount> <SIP Start Date> <Installments>\n";
}
