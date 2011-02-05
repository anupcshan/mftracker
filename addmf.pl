#!/usr/bin/perl

use DBI;

my $dbh, $mf, @qresult, $checkmfexistsquery, $insertquery;
$dbh = DBI->connect("dbi:SQLite:dbname=/home/anup/.mftracker/mftracker.db", "", "");

foreach $argnum (0 .. $#ARGV) {
	$mf = $ARGV[$argnum];

	$checkmfexistsquery = "SELECT COUNT(*) FROM mfinfo WHERE mfid = '$mf'";
	@qresult = $dbh->selectall_arrayref($checkmfexistsquery);
	if ($qresult[0][0][0] == 0) {
		print "Adding $mf...\n";
		$insertquery = "INSERT INTO mfinfo VALUES('$mf', '', 0)";
		$dbh->do($insertquery);
	}
	else {
		print "$mf exists in the database. Skipping...\n";
	}
}
