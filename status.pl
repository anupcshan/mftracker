#!/usr/bin/perl

use DBI;

$home = $ENV{"HOME"};
$dbloc = $home."/.mftracker/mftracker.db";
$dbh = DBI->connect("dbi:SQLite:dbname=".$dbloc, "", "");

sub getstatusformf() {
	my ($mfid, $mfname) = @_;
	my $buyquery = "SELECT SUM(quantity), SUM(quantity * buyprice) FROM portfolio WHERE mfid = '$mfid'";
	my $qresult = $dbh->selectall_arrayref($buyquery);
	my ($quantity, $total) = @{@$qresult[0]};
	my $avgbuyprice = $total / $quantity;
	$avgbuyprice = (int(($avgbuyprice * 1000) + 0.5)) / 1000;
	$total = (int(($total * 1000) + 0.5)) / 1000;

	my $currentnavquery = "SELECT nav FROM navhistory WHERE mfid = '$mfid' AND date = (SELECT MAX(date) FROM navhistory WHERE mfid = '$mfid')";
	$qresult = $dbh->selectall_arrayref($currentnavquery);
	my ($currentprice) = @{@$qresult[0]};
	my $currentvalue = $currentprice * $quantity;
	my $gain = $currentvalue - $total;
	my $pctgain = $gain / $total * 100;
	printf ("%40s %8.3f %10.3f %8.3f %8.3f %10.3f %10.3f %8.3f%\n", $mfname, $quantity, $total, $avgbuyprice, $currentprice, $currentvalue, $gain, $pctgain);
	return ($total, $currentvalue);
}

sub getstatusbymf() {
	print "=" x 110, "\n";
	printf ("%40s %8s %10s %8s %8s %10s %10s %9s\n", 'Name', 'Units', 'Total', 'Avg Cost', 'Cur Cost', 'Cur Value', 'Gain', 'Pct Gain');
	print "-" x 110, "\n";
	my $listportfoliosquery = "SELECT mfid, mfname FROM mfinfo WHERE mfid IN (SELECT DISTINCT mfid FROM portfolio)";
	my $qresult = $dbh->selectall_arrayref($listportfoliosquery);
	my $totalbuyvalue = 0, $totalcurrentvalue = 0;
	for my $mfrow (@$qresult) {
		my ($mfid, $mfname) = @$mfrow;
		my ($buyvalue, $currentvalue) = &getstatusformf($mfid, $mfname);
		$totalbuyvalue += $buyvalue;
		$totalcurrentvalue += $currentvalue;
	}
	my $gain = $totalcurrentvalue - $totalbuyvalue;
	my $pctgain = $gain / $totalbuyvalue * 100;
	print "-" x 110, "\n";
	printf ("%40s %19.3f %28.3f %10.3f %8.3f%\n", 'Total', $totalbuyvalue, $totalcurrentvalue, $gain, $pctgain);
	print "=" x 110, "\n";
}

&getstatusbymf();
