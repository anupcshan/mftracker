#!/bin/bash
DIR=/tmp/mftracker
MFSTATUSFILE=$DIR/invest.csv
SENSEXCSV=$DIR/sensex.csv
SENSEXDAT=$DIR/sensex.dat

mkdir -p $DIR
./mftracker.pl exportcsv > $MFSTATUSFILE
sed -i 1d $MFSTATUSFILE
sed -i "s/,/ /g" $MFSTATUSFILE

wget -c -q "http://ichart.finance.yahoo.com/table.csv?s=%5EBSESN&a=00&b=5&c=2011&g=d&ignore=.csv" -O $SENSEXCSV
cp $SENSEXCSV $SENSEXDAT
sed -i 1d $SENSEXDAT
for line in `cat $SENSEXDAT`
do
    today=`echo $line | grep -o "[0-9.]*$"`
    relative=`echo "scale=4; ($today-20301.10)/203.0110" | bc`
    sed -i "s/$line/$line,$relative/" $SENSEXDAT
done
sed -i "s/,/ /g" $SENSEXDAT
sed -i "s/\([0-9]\)\-/\1\//g" $SENSEXDAT

cat << EOF > $DIR/gnuplot.scr
set xdata time
set timefmt "%Y/%m/%d"
plot "$MFSTATUSFILE" using 1:5 with lines title 'Profit'
replot "$SENSEXDAT" using 1:8 with lines title 'Sensex'
set terminal png size 1440,900
set output "$DIR/graph.png"
replot
EOF

gnuplot $DIR/gnuplot.scr
eog $DIR/graph.png &
