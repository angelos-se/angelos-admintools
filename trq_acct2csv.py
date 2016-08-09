#!/usr/bin/python
# This script reads Torque accounting files (usually located at torque/server_priv/accounting)
# and generates CSV file that can be used for pivot reporting in spreadsheet applications
#
# Usage: tra_acct2csv.py $TORQUE_HOME/server_priv/accounting/201607* > ~/usage_report_201607.csv

import sys, datetime
neededfields = (
"user", "group", "Job_Id", "jobname", "queue", "start_date", "start_time",
"total_execution_slots", "unique_node_count", "Exit_status", "resources_used.walltime",
"resources_used.walltime_cpuhour"
)
reportlist = []

def printheader(fields=()):
	for i in fields:
		print i+",",
	print ""

def printcsv(fields=(), data={}):
	for i in fields:
		print str(data.get(i, ""))+",",
	print ""

def readacct(acctfile=""):
	global reportlist
	try:
		accthandle = open(acctfile)
		# Only processing exiting lines
		for line in [i for i in accthandle if i.split(';')[1] == 'E']:
			jobdict = {}
			line = line.strip().split(';')	# Removing trailing new line and break line into components
			jobdesc = line[3].split(' ')	# Break component into properties
			jobdict['Job_Id'] = line[2]		# Fixed field
			for property in jobdesc:
				property = property.split('=')
				jobdict[property[0]] = property[1]

			# Calculate extra fields
			# This part has been heavily edited on GitHub and not been tested
			try:
				t_fields = jobdict["resources_used.walltime"].split(":")
				jobdict["resources_used.walltime_sec"] = int(t_fields[0])*3600 + \
				int(t_fields[1])*60 + int(t_fields[2])
			except: raise # or pass? Actually you can safely ignore it usually
			try:
				startdatetime = datetime.datetime.fromtimestamp(int(jobdict["start"]))
				jobdict["start_date"] = startdatetime.strftime("%Y-%m-%d")
				jobdict["start_time"] = startdatetime.strftime("%H:%M:%S")
			except: raise # or pass? Actually you can safely ignore it usually	
			try:
				cpu = int(jobdict["total_execution_slots"])
				wallsec = int(jobdict["resources_used.walltime_sec"])
				jobdict["resources_used.walltime_cpuhour"] = cpu * wallsec / 3600.0
			except: raise # or pass? Actually you can safely ignore it usually
			
			reportlist.append(jobdict)
	except: raise # We don't expect something to break in this try block, always raise

def main(argv):
	for acctfile in argv:		# open report files
		readacct(acctfile)
	printheader(neededfields)	# print header as defined by needed fields
	for i in reportlist:		# print report body
		printcsv(neededfields, i)

if __name__ == "__main__":
	main(sys.argv[1:])[angelosching@hk181 trq-account2csv]$ 
