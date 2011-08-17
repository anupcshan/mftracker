#!/bin/bash
DIR=/tmp/mftracker
MFSTATUSFILE=$DIR/invest.csv
SENSEXCSV=$DIR/sensex.csv
DATAFILE=$DIR/data.dat

rm -rf $DIR
mkdir -p $DIR
./mftracker.pl exportcsv > $MFSTATUSFILE
sed -i 1d $MFSTATUSFILE
sed -i "s/,/ /g" $MFSTATUSFILE

wget -c -q "http://ichart.finance.yahoo.com/table.csv?s=%5EBSESN&a=00&b=5&c=2011&g=d&ignore=.csv" -O $SENSEXCSV
cp $SENSEXCSV $DATAFILE
sed -i 1d $DATAFILE
firstdate=`cut -d ',' -f 1 $DATAFILE | sort | head -n1`
startsensex=`grep "$firstdate" $DATAFILE | cut -d ',' -f 7`
for line in `cat $DATAFILE`
do
    date=`echo $line | grep -o "^[0-9-]*" | sed "s#-#/#g"`
    profit=`grep "$date" $MFSTATUSFILE | cut -d ' ' -f 5`
    today=`echo $line | cut -d ',' -f 7`
    relative=`echo "scale=4; 100*($today-$startsensex)/$startsensex" | bc`
    change=`echo "$profit - $relative" | bc`
    sed -i "s#$line#$date,$today,$relative,$change#" $DATAFILE
done
sed -i "s/,/ /g" $DATAFILE
sed -i "s/\([0-9]\)\-/\1\//g" $DATAFILE

cat << EOF > $DIR/gnuplot.scr
set xdata time
set timefmt "%Y/%m/%d"
plot "$MFSTATUSFILE" using 1:5 with lines title 'Profit'
replot "$DATAFILE" using 1:3 with lines title 'Sensex'
replot "$DATAFILE" using 1:4 with lines title 'Change'
replot 0 with lines title 'Zero'
set terminal png size 1440,900
set output "$DIR/graph.png"
replot
EOF

gnuplot $DIR/gnuplot.scr
eog $DIR/graph.png &
