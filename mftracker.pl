#!/usr/bin/perl
#
# Copyright (C) 2011 Anup C Shan
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
# USA

use HTTP::Request::Common qw(POST GET);
use LWP::UserAgent;
use Date::Manip;
use DBI;
use Switch;

$ua = new LWP::UserAgent;
$ua->env_proxy;
$home = $ENV{"HOME"};
$dbloc = $home."/.mftracker/mftracker.db";
$dbh = DBI->connect("dbi:SQLite:dbname=".$dbloc, "", "");

sub fetchnavs() {
	my $datetime = $_[0];
	my $mfid = $_[1];
	my $direction = $_[2] || -1;
	my @sch_name = split (/\|/, $mfid);
	my $day = substr ($datetime, 6, 2), $month = substr ($datetime, 4, 2), $year = substr ($datetime, 0, 4);
	my $request = POST 'http://www.mutualfundsindia.com/historical_nav_rpt.asp',
			[sch_name => $sch_name[0], sch_name1 => $sch_name[1], day1 => $day, mon1 => $month, year1 => $year];
	my $response = $ua->request($request);
	my $body = $response->content;
	my $date = "", $nav = 0, $isdate = 0;
	my $retdatetime = "00000000";

	for(reverse (split /\n/, $body)) {
		my($line) = $_;
		chomp($line);
		if($line =~ /<td align="left" valign="middle" bgcolor="#FFFFFF" class="bluebig">/) {
			$line =~ s/<[^>]*>//g;
			$line =~ s/^\s*//;
			$line =~ s/\s*$//;
			if ($isdate) {
				$date = `date --date="$line" "+%Y%m%d"`;
				$date =~ s/\s*$//;
				$isdate = 0;

				# Got date,nav pair. Add to DB now...
				my $insertsuccessful = 0;
				my $query = "INSERT INTO navhistory VALUES('$mfid', $nav, $date)";
				$dbh->do($query) && ($insertsuccessful = 1);

				if ($insertsuccessful) {
					print "Adding $date :: $nav\n";

					if ($direction == -1) {
						$retdatetime = $date;
					}
					if ($retdatetime == "00000000" && $direction == 1) {
						$retdatetime = $date;
					}
				}
			}
			else {
				$nav = $line;
				$isdate = 1;
			}
		}
	}

	return $retdatetime;
}


sub fetchallnavs() {
	my $mfid = $_[0];
	my $enddate = $_[1], $retdate, $mindate, $startdate, $maxdate;
	my @qresult, $maxdatequery;
	# Start from yesterday. Daily NAV values are updated just after midnight.
	$startdate = UnixDate(DateCalc(ParseDate("today"), "- 1 days"), "%Y%m%d");
	my $histcountquery = "SELECT COUNT(*) FROM navhistory WHERE mfid = '$mfid'";
	@qresult = $dbh->selectall_arrayref($histcountquery);
	if ($qresult[0][0][0] > 0) {
		$maxdatequery = "SELECT MAX(date) FROM navhistory WHERE mfid = '$mfid'";
		@qresult = $dbh->selectall_arrayref($maxdatequery);
		$maxdate = $qresult[0][0][0];
		if ($startdate != $maxdate) {
			$startdate = $maxdate;
			while (1) {
				$retdate = &fetchnavs($startdate, $mfid, 1);
				if ($retdate == "00000000") {
					last;
				}
				if ($retdate <= $enddate) {
					last;
				}
				$startdate = UnixDate(DateCalc($retdate, "+ 4 days"), "%Y%m%d");
			}
		}

		my $mindatequery = "SELECT MIN(date) FROM navhistory WHERE mfid = '$mfid'";
		@qresult = $dbh->selectall_arrayref($mindatequery);
		$startdate = $mindate = $qresult[0][0][0];
		$startdate = UnixDate(DateCalc($startdate, "- 5 days"), "%Y%m%d");
		if ($startdate <= $enddate) {
			return 0;
		}
	}

	print "Starting from $startdate\n";
	while (1) {
		$retdate = &fetchnavs($startdate, $mfid, -1);
		if ($retdate == "00000000") {
			# In case an entire week is missing from NAV history.
			$retdate = UnixDate(DateCalc($startdate, "- 1 days"), "%Y%m%d");
		}
		if ($retdate <= $enddate) {
			print $mindate." :: ".$enddate."\n";
			if ($mindate > $enddate) {
				# In case the MF doesn't have NAV's for some days since its inception date,
				# change its inception date in DB.
				my $updatemfdatequery = "UPDATE mfinfo SET startdate = $mindate WHERE mfid = '$mfid'";
				$dbh->do($updatemfdatequery);
			}
			return 0;
		}
		$startdate = UnixDate(DateCalc($retdate, "- 5 days"), "%Y%m%d");
	}
}

sub getandupdatemfinfo() {
	my $mfid = $_[0];
	my ($amc_name, $sch_name) = split (/\|/, $mfid);
	my $mfname = "";
	my $startdate = 0;

	my $response = $ua->request(GET "http://www.mutualfundsindia.com/fund_facts_rpt.asp?scheme=".$sch_name);
	my $body = $response->content;
	my $isnextname = 0;
	my $isnextdate = 0;

	for(split /\n/, $body) {
		my($line) = $_;
		chomp($line);
		if($line =~ /class="head"/) {
			$isnextname = 1;
			next;
		}
		if($line =~ /Inception Date/) {
			$isnextdate = 1;
			next;
		}
		if ($isnextname == 1) {
			$line =~ s/<[^>]*>//g;
			$line =~ s/^\s*//;
			$line =~ s/\s*$//;
			$mfname = $line;
			print $mfid." is ".$mfname."\n";
			my $updatemfnamequery = "UPDATE mfinfo SET mfname = '$mfname' WHERE mfid = '$mfid'";
			$dbh->do($updatemfnamequery);
			$isnextname = 0;
		}
		if ($isnextdate == 1) {
			$line =~ s/<[^>]*>//g;
			$line =~ s/&nbsp;//g;
			$line =~ s/^\s*//;
			$line =~ s/\s*$//;
			$startdate = UnixDate(ParseDate("$line"), "%Y%m%d");
			print $mfname." started on ".$startdate."\n";
			my $updatemfdatequery = "UPDATE mfinfo SET startdate = $startdate WHERE mfid = '$mfid'";
			$dbh->do($updatemfdatequery);
			$isnextdate = 0;
		}
	}

	return ($mfname, $startdate);
}

sub updateallmfs() {
	my $listmfsquery = "SELECT mfid, mfname, startdate FROM mfinfo";
	my $qresult = $dbh->selectall_arrayref($listmfsquery);
	for my $mfrow (@$qresult) {
		my ($mfid, $mfname, $startdate) = @$mfrow;
		if ($mfname =~ /^$/ || $startdate == 0) {
			($mfname, $startdate) = &getandupdatemfinfo($mfid);
		}
		print "Updating data for $mfname...\n";
		&fetchallnavs($mfid, $startdate);
	}
}

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

		my $holdingexistsquery = "SELECT COUNT(*) FROM portfolio WHERE buydate >= $sipdate and sipid = '$sipid'";
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

sub getmfbuyquery() {
	my ($mfid) = @_;
	my $buyquery = "SELECT SUM(quantity), SUM(quantity * buyprice) FROM portfolio WHERE mfid = '$mfid'";
	return $buyquery;
}

sub getsipbuyquery() {
	my ($sipid) = @_;
	my $buyquery = "SELECT SUM(quantity), SUM(quantity * buyprice) FROM portfolio WHERE sipid = '$sipid'";
	return $buyquery;
}

sub getmfcommitmentquery() {
	my ($mfid) = @_;
	my $commitmentquery = "SELECT SUM(sipamount * installments) FROM sips WHERE mfid = '$mfid'";
	return $commitmentquery;
}

sub getsipcommitmentquery() {
	my ($sipid) = @_;
	my $commitmentquery = "SELECT SUM(sipamount * installments) FROM sips WHERE sipid = '$sipid'";
	return $commitmentquery;
}

sub getstatusformfsip() {
	my ($mfid, $mfname, $buyquery, $commitmentquery) = @_;
	my $qresult = $dbh->selectall_arrayref($buyquery);
	my ($quantity, $total) = @{@$qresult[0]};
	$qresult = $dbh->selectall_arrayref($commitmentquery);
	my ($commitment) = @{@$qresult[0]};

	my $avgbuyprice = 0;
	if ($quantity != 0) {
		$avgbuyprice = $total / $quantity;
		$avgbuyprice = (int(($avgbuyprice * 1000) + 0.5)) / 1000;
	}
	$total = (int(($total * 1000) + 0.5)) / 1000;

	my $currentnavquery = "SELECT nav FROM navhistory WHERE mfid = '$mfid' AND date = (SELECT MAX(date) FROM navhistory WHERE mfid = '$mfid')";
	$qresult = $dbh->selectall_arrayref($currentnavquery);
	my ($currentprice) = @{@$qresult[0]};
	my $currentvalue = $currentprice * $quantity;
	my $gain = $currentvalue - $total;
	my $pctgain = 0;
	if ($total != 0) {
		$pctgain = $gain / $total * 100;
	}
	printf ("%50s %8.3f %10.3f %8.3f %8.3f %10.3f %10.3f %8.3f%% %11.3f\n", $mfname, $quantity, $total, $avgbuyprice, $currentprice, $currentvalue, $gain, $pctgain, $commitment);
	return ($total, $currentvalue, $commitment);
}

sub getstatusbymf() {
	print "=" x 132, "\n";
	printf ("%50s %8s %10s %8s %8s %10s %10s %9s %11s\n", 'Name', 'Units', 'Total', 'Avg Cost', 'Cur Cost', 'Cur Value', 'Gain', 'Pct Gain', 'Commitment');
	print "-" x 132, "\n";
	my $listportfoliosquery = "SELECT mfid, mfname FROM mfinfo WHERE mfid IN (SELECT DISTINCT mfid FROM portfolio)";
	my $qresult = $dbh->selectall_arrayref($listportfoliosquery);
	my $totalbuyvalue = 0, $totalcurrentvalue = 0, $totalcommitment = 0;
	for my $mfrow (@$qresult) {
		my ($mfid, $mfname) = @$mfrow;
		my ($buyvalue, $currentvalue, $commitment) = &getstatusformfsip($mfid, $mfname, &getmfbuyquery($mfid), &getmfcommitmentquery($mfid));
		$totalbuyvalue += $buyvalue;
		$totalcurrentvalue += $currentvalue;
		$totalcommitment += $commitment;
	}
	my $gain = $totalcurrentvalue - $totalbuyvalue;
	my $pctgain = $gain / $totalbuyvalue * 100;
	print "-" x 132, "\n";
	printf ("%50s %19.3f %28.3f %10.3f %8.3f%% %11.3f\n", 'Total', $totalbuyvalue, $totalcurrentvalue, $gain, $pctgain, $totalcommitment);
	print "=" x 132, "\n";
}

sub getstatusbysip() {
	print "=" x 132, "\n";
	printf ("%50s %8s %10s %8s %8s %10s %10s %9s %11s\n", 'Name', 'Units', 'Total', 'Avg Cost', 'Cur Cost', 'Cur Value', 'Gain', 'Pct Gain', 'Commitment');
	print "-" x 132, "\n";
	my $listportfoliosquery = "SELECT s.sipid, s.mfid, m.mfname FROM sips s, mfinfo m WHERE s.mfid = m.mfid";
	my $qresult = $dbh->selectall_arrayref($listportfoliosquery);
	my $totalbuyvalue = 0, $totalcurrentvalue = 0, $totalcommitment = 0;
	for my $mfrow (@$qresult) {
		my ($sipid, $mfid, $mfname) = @$mfrow;
		my ($buyvalue, $currentvalue, $commitment) = &getstatusformfsip($mfid, $mfname, &getsipbuyquery($sipid), &getsipcommitmentquery($sipid));
		$totalbuyvalue += $buyvalue;
		$totalcurrentvalue += $currentvalue;
		$totalcommitment += $commitment;
	}
	my $gain = $totalcurrentvalue - $totalbuyvalue;
	my $pctgain = $gain / $totalbuyvalue * 100;
	print "-" x 132, "\n";
	printf ("%50s %19.3f %28.3f %10.3f %8.3f%% %11.3f\n", 'Total', $totalbuyvalue, $totalcurrentvalue, $gain, $pctgain, $totalcommitment);
	print "=" x 132, "\n";
}

sub addmf() {
	my $mf = $_[0];
	my $checkmfexistsquery = "SELECT COUNT(*) FROM mfinfo WHERE mfid = '$mf'";
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

sub delsip() {
	my $sipid = $_[0];
	my $checksipexistsquery = "SELECT COUNT(*) FROM sips WHERE sipid = '$sipid'";
	@qresult = $dbh->selectall_arrayref($checksipexistsquery);
	if ($qresult[0][0][0] != 0) {
		print "Deleting portfolio entries for sip $sipid...\n";
		$holdingsdeletequery = "DELETE FROM portfolio WHERE sipid = $sipid";
		$dbh->do($holdingsdeletequery);

		print "Deleting sip $sipid...\n";
		$sipdeletequery = "DELETE FROM sips WHERE sipid = $sipid";
		$dbh->do($sipdeletequery);
	}
	else {
		print "$sipid does not exist in the database. Skipping...\n";
	}
}

sub addsip() {
	my ($mfid, $sipamount, $sipdate, $installments) = @_;
	my $checkmfexistsquery = "SELECT COUNT(*) FROM mfinfo WHERE mfid = '$mfid'";
	@qresult = $dbh->selectall_arrayref($checkmfexistsquery);
	if ($qresult[0][0][0] == 0) {
		print "Adding $mfid...\n";
		$insertquery = "INSERT INTO mfinfo VALUES('$mfid', '', 0)";
		$dbh->do($insertquery);
	}
	print "Adding sip for $mfid...\n";
	$insertquery = "INSERT INTO sips VALUES(NULL, '$mfid', $sipamount, $sipdate, $installments, 0)";
	$dbh->do($insertquery);
}

sub dailyjob() {
	# Hide output of updation process
	open CPOUT, '>&STDOUT';
	open STDOUT, '>/dev/null';

	&updateallmfs();
	&updateallsips();

	# Reopen stdout
	close STDOUT;
	open STDOUT, '>&CPOUT';

	&getstatusbymf();
}

sub showdates() {
	print "=" x 14, "\n";
	printf ("%5s %8s\n", 'Date', 'Amount');
	print "-" x 14, "\n";
	my $sipsdayquery = "SELECT DISTINCT sipdate%100 day, SUM(sipamount) FROM sips GROUP BY day ORDER BY day";
	my $qresult = $dbh->selectall_arrayref($sipsdayquery);
	my $totalamount = 0;
	my $currentday = UnixDate(ParseDate("today"), "%d");
	my $foundcurrentday = 0;
	for my $mfrow (@$qresult) {
		my ($day, $amount) = @$mfrow;
		if ($foundcurrentday == 0 && $day >= $currentday) {
			printf ("->%3d %8d\n", $day, $amount);
			$foundcurrentday = 1;
		}
		else {
			printf ("%5d %8d\n", $day, $amount);
		}
		$totalamount += $amount;
	}
	print "-" x 14, "\n";
	printf ("%5s %8d\n", '', $totalamount);
	print "=" x 14, "\n";
}

sub showhelp() {
	print "Usage: mftracker.pl <command> <arguments>\n";
	print "Commands: \n";
	print "    1) fetch      - Fetch NAV values for all MFs in DB.\n";
	print "    2) updatesips - Update portfolio holdings for SIPs.\n";
	print "    3) status     - Print current portfolio status.\n";
	print "    4) sipstatus  - Print current portfolio status per SIP.\n";
	print "    5) addmf      - Add a new MF into the DB.\n";
	print "    6) addsip     - Add a new SIP into the DB.\n";
	print "    7) delsip     - Deleta a SIP and its portfolio entries from the DB.\n";
	print "    8) daily      - Perform fetch, updatesips and status operations.\n";
	print "    9) dates      - Print distribution of sip dates over a month.\n";
	print "   10) help       - Show this help message.\n";
}

open STDERR, '>/dev/null';
if ($#ARGV >= 0) {
	my $command = $ARGV[0];
	switch ($command) {
		case "fetch" {
			&updateallmfs();
		}
		case "updatesips" {
			&updateallsips();
		}
		case "status" {
			&getstatusbymf();
		}
		case "sipstatus" {
			&getstatusbysip();
		}
		case "addmf" {
			if ($#ARGV == 0) {
				print "[Error] Need to provide at least 1 MF ID to add.\n";
				last;
			}
			foreach $argnum (1 .. $#ARGV) {
				my $mf = $ARGV[$argnum];
				&addmf($mf);
			}
		}
		case "addsip" {
			if ($#ARGV != 4) {
				print "Usage: mftracker.pl addsip <MFId> <SIP Amount> <SIP Start Date> <Installments>\n";
				last;
			}
			else {
				my ($command, $mfid, $sipamount, $sipdate, $installments) = @ARGV;
				&addsip($mfid, $sipamount, $sipdate, $installments);
			}
		}
		case "delsip" {
			if ($#ARGV == 0) {
				print "[Error] Need to provide at least 1 SIP ID to delete.\n";
				last;
			}
			foreach $argnum (1 .. $#ARGV) {
				my $sipid = $ARGV[$argnum];
				&delsip($sipid);
			}
		}
		case "daily" {
			&dailyjob();
		}
		case "dates" {
			&showdates();
		}
		case "help" {
			&showhelp();
		}
		else {
			print "[Error] Command $command not recognized.\n";
			&showhelp();
		}
	}
}
else {
	&showhelp();
}
close STDERR;
