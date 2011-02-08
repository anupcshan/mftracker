#!/usr/bin/perl

use DBI;

my $dbh, $mf, @qresult, $checkmfexistsquery, $insertquery;
$dbh = DBI->connect("dbi:SQLite:dbname=/home/anup/.mftracker/mftracker.db", "", "");

sub addsip() {
	my ($mfid, $sipamount, $sipdate, $installments) = @_;
	print "Adding sip for $mfid...\n";
	$insertquery = "INSERT INTO sips VALUES(NULL, '$mfid', $sipamount, $sipdate, $installments)";
	$dbh->do($insertquery);
}


if ($#ARGV == 3) {
	my ($mfid, $sipamount, $sipdate, $installments) = @ARGV;
	&addsip($mfid, $sipamount, $sipdate, $installments);
}
else {
	print "Usage: addsip.pl <MFId> <SIP Amount> <SIP Start Date> <Installments>\n";
}
