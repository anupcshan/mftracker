#!/usr/bin/perl

use HTTP::Request::Common qw(POST GET);
use LWP::UserAgent;
use Date::Manip;
use DBI;

$ua = new LWP::UserAgent;
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

open STDERR, '>/dev/null';
updateallmfs();
close STDERR;
