#!/usr/bin/perl

use DBI;
use Date::Manip;

$dbh = DBI->connect("dbi:SQLite:dbname=/home/anup/.mftracker/mftracker.db", "", "");

sub updatesip() {
	my ($sipid, $mfid, $sipamount, $sipdate, $installments) = @_;
	my $today = UnixDate(ParseDate("today"), "%Y%m%d");
	print "Updating SIPs for $sipid...\n";
	my @qresult;

	while ($sipdate <= $today) {
		# Find if (>=sipdate, mfid) is already in portfolio.
		# If yes, go to next sipdate.
		# Else, if sipdate <= today and NAV data exists for sipdate,
		# add new entry to portfolio.

		my $holdingexistsquery = "SELECT COUNT(*) FROM portfolio WHERE buydate >= $sipdate and mfid = '$mfid'";
		@qresult = $dbh->selectall_arrayref($holdingexistsquery);
		if ($qresult[0][0][0] == 0) {
			my $buydatequery = "SELECT MIN(date) FROM (SELECt * FROM navhistory WHERE mfid = '$mfid' AND date >= $sipdate)";
			@qresult = $dbh->selectall_arrayref($buydatequery);
			my $buydate = $qresult[0][0][0];

			if ($buydate =~ /^$/) {
				# If no NAV entry since buydate,
				# wait till next fetch to get new NAV entry.
				return 0;
			}

			my $navquery = "SELECT nav FROM navhistory WHERE mfid = '$mfid' AND date = $buydate";
			@qresult = $dbh->selectall_arrayref($navquery);
			my $buyprice = $qresult[0][0][0];

			my $quantity = $sipamount / $buyprice;
			# Rounding off to nearest 3 decimal digits.
			$quantity = (int(($quantity * 1000) + 0.5)) / 1000;

			print "Adding ".$quantity." units of ".$mfid." on ".$buydate." at ".$buyprice."\n";
			my $insertquery = "INSERT INTO portfolio VALUES(NULL, '$mfid', $sipid, $buydate, $buyprice, $quantity)";
			$dbh->do($insertquery);
		}
		$sipdate = UnixDate(DateCalc($sipdate, "+ 1 month"), "%Y%m%d");
	}
}

sub updateallsips() {
	my $listsipsquery = "SELECT sipid, mfid, sipamount, sipdate, installments FROM sips";
	my $qresult = $dbh->selectall_arrayref($listsipsquery);
	for my $mfrow (@$qresult) {
		my ($sipid, $mfid, $sipamount, $sipdate, $installments) = @$mfrow;
		&updatesip($sipid, $mfid, $sipamount, $sipdate, $installments);
	}
}

&updateallsips();
