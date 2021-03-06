#!/usr/bin/env perl
use strict;
use diagnostics;
use Cwd;
use List::Util qw[min];
use File::Spec;

# Run a set of tests in paralel on multiple machines and create a
# report with the status of each test and run-time.
# README.txt has more details.
MAIN:{

  if (scalar(@ARGV) < 1){
    print "Usage: $0 <configFile> <testList>\n";
    exit(1);
  }

  print "Starting ...\n";

  my $binPath = bin_path();
  my $baseDir = getcwd;
  $baseDir    =~ s/\/*\s*$//g;

  my $configFile = shift @ARGV;
  my ($runDirs, $machines, $numProc, $strictValidation, $errors)
     = parse_job_file($configFile);

  # If a list of tests is passed from the command line, over-ride the list
  # read from the config file.
  if (scalar(@ARGV) > 0){
    $runDirs = \@ARGV;
    print "Will run the tests: " . join(" ", @$runDirs) . "\n";
  }
  
  # Don't run tests on inaccessible or overloaded machines.
  for (my $i = 0; $i < scalar(@$machines); $i++){
    my $beg = time;
    my $machine = $machines->[$i];
    my @ans = qx(ssh $machine ls /);
    my $end = time;
    if ((scalar(@ans) == 0 || $end - $beg > 2) && scalar(@$machines) > 1){
      print "Removing $machine as it is inaccessible or too slow\n";
      splice(@$machines, $i, 1);
      splice(@$numProc, $i, 1);
    }
  }

  # When launching runs, first start the ones which take longest.
  my $reportFile = "report.txt";
  my $prevRunsTAT = read_report($reportFile);

  mark_all_as_not_started($baseDir, $runDirs, $machines);
  my $numRuns = scalar(@$runDirs);

  # Run a loop until all jobs are finished
  my %dispatchedCount;
  while (1){

    my ($numDone, %numRunning, @notStarted);
    get_status_of_all($baseDir, $runDirs, $machines,        # inputs
                      \$numDone, \%numRunning, \@notStarted # outputs
                     );
    last if ($numDone == $numRuns); # Finished

    my $numNotStartedJobs = scalar(@notStarted);

    # Need this logic to put the runs which we already attempted to start
    # to the end of the queue and the runs which take longest to the top
    # of the queue.
    my %notStartedHash;
    foreach my $job (@notStarted){
      my $prevTAT = 0;
      $prevTAT = $prevRunsTAT->{$job} if (exists $prevRunsTAT->{$job});
      if (exists $dispatchedCount{$job}){
        $notStartedHash{$job} = $dispatchedCount{$job} - $prevTAT/1000;
      }else{
        $notStartedHash{$job} = -$prevTAT/1000;
      }
    }

    my @unusedProc = get_unused_processes($machines, $numProc, \%numRunning);
    my $numUnusedProc = scalar (@unusedProc);

    my $totalNumRunning = 0;
    foreach my $key (keys %numRunning){
      $totalNumRunning += $numRunning{$key};
    }
    print "Not started: $numNotStartedJobs. Running: $totalNumRunning. " .
       "Num unused processes: $numUnusedProc.\n";

    if ( $numNotStartedJobs == 0 || # no more runs to start
         $numUnusedProc  == 0 ){ # no unused processes
      sleep 5; # Wait for jobs to complete
      next;
    }

    my $numToRun = min($numNotStartedJobs, $numUnusedProc);
    my $c = 0;
    foreach my $job (sort { $notStartedHash{$a} <=> $notStartedHash{$b} }
                              keys %notStartedHash ){
      dispatchRun($job, $baseDir, $unusedProc[$c], $binPath, $configFile);
      $dispatchedCount{$job}++; # Count how many times a job was started
      $c++;
      last if ($c >= $numToRun);
      sleep 1;
    }

  }

  # Save the report
  write_report($reportFile, $baseDir, $runDirs);

  # Send the report by email
  my $user = qx(whoami); $user =~ s/\s*$//g;
  system("mailx $user -s 'Status of tests' < $reportFile > /dev/null 2>&1");
}

sub bin_path{

  # Instruct the script to get its dependencies from the same location
  # where the script itself resides.

  my $binPath = File::Spec->rel2abs( __FILE__ );
  $binPath =~ s!^(.*)/.*$!$1!g;

  push(@INC, $binPath);
  require 'test_utils.pl';

  return $binPath;
}
