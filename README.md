# Alma Analytics monitoring

## Foibles

- paal = process alma analytics log.

- For the current day the current state is assumed to last till the end
of the day.

- There is a lot of plumbing between a local API call to analytics and
Analytics at the data centre. All of which affects response times.

## How it works

The script `check_analytics` make an API call to Alma Analytics. You can
use any of your own reports (choose a lightweight one). The output of
this script is for input to Nagios/Check-MK infrastructure monitoring
tools but it also creates a log file with entries like:


    20150813:142825 up time=0.628s
    20150813:142928 up time=3.474s

This log file is used as input to the lua script `paal.lua` which computes
the averages for response and calculates the daily uptimes. It uses
`paal_template.html` and inserts javascript statements and writes out
`paal.html`. Google Charts are used to display the graphs.

You will need some scaffolding to collect the log from wherever it is
generated, run the lua script over it and move the result to somewhere
for viewing.

## To do

- Store the log entries and results in a database rather than keep
processing the whole log file. Then it should be possible to plug the
graphs into a datasource rather than generating a page with all the
data in it. Currently runs fast but as the logfile grows ..... It will
do for now.

- Clean up the mess that is paal_template.html.

- Probably many other things should someone be interested.

